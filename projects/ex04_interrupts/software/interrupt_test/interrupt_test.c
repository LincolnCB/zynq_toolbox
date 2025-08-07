#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>

//////////////////// Mapped Memory Definitions ////////////////////

// Addresses are defined in the hardware design Tcl file
#define AXI_CFG  (uint32_t) 0x40000000
#define CFG_SIZE (uint32_t) 64 / 8 // Size of the configuration register in bytes
// Add to a header file or at the top of your C file
#define BYTE_TO_BINARY_PATTERN "%c%c%c%c%c%c%c%c"
#define BYTE_TO_BINARY(byte)   \
  ((byte) & 0x80 ? '1' : '0'), \
  ((byte) & 0x40 ? '1' : '0'), \
  ((byte) & 0x20 ? '1' : '0'), \
  ((byte) & 0x10 ? '1' : '0'), \
  ((byte) & 0x08 ? '1' : '0'), \
  ((byte) & 0x04 ? '1' : '0'), \
  ((byte) & 0x02 ? '1' : '0'), \
  ((byte) & 0x01 ? '1' : '0')

//////////////////// Interrupt State Variables ////////////////////

uint8_t irq_status[8]; // Array to hold the status of each interrupt (0-7)
pthread_mutex_t irq_mutexes[8]; // Mutexes for each interrupt to ensure thread safety 

//////////////////// Function Prototypes ////////////////////

// Print out the available commands
void print_help();
// Set a single interrupt
void set_interrupt(volatile void *cfg, uint32_t interrupt_num, uint32_t value);
// Set multiple interrupts to a value with an 8-bit mask
void set_interrupt_mask(volatile void *cfg, uint8_t mask, uint32_t value);
// Set all the interrupts to a single given bit
void set_all_interrupts(volatile void *cfg, uint32_t value);
// Hard set the interrupts to the given 8-bit value
void hard_set_all_interrupts(volatile void *cfg, uint8_t value);
// Clear a single interrupt (on the PS side)
void clear_interrupt(uint32_t interrupt_num);
// Clear multiple interrupts with an 8-bit mask (on the PS side)
void clear_interrupt_mask(uint8_t mask);
// Clear all interrupts (on the PS side)
void clear_all_interrupts();
// Thread function to handle interrupt detection
void *interrupt_thread_func(void *arg);


//////////////////// Main ////////////////////
int main()
{

  //////////////////// 1. Setup ////////////////////
  printf("Test program for PS/PL interrupts\n");
  printf("Setup:\n");

  // Initialize mutex and status for each interrupt
  printf("Initializing interrupt status and mutexes...\n");
  for (int i = 0; i < 8; i++) {
    irq_status[i] = 0; // Initialize status to 0 (not pending)
    pthread_mutex_init(&irq_mutexes[i], NULL); // Initialize mutex for each interrupt
  }

  int fd; // File descriptor
  volatile void *cfg; // CFG register AXI interface

  // Open the device file
  printf("Opening device file /dev/mem...\n");
  fd = open("/dev/mem", O_RDWR);
  if(fd < 0) {
    perror("Failed to open /dev/mem");
    return EXIT_FAILURE;
  }
  printf("Device file opened successfully.\n");

  // Get the page size for memory mapping
  long pagesize = sysconf(_SC_PAGE_SIZE);
  if(pagesize < 0) {
    perror("Failed to get page size");
    close(fd);
    return EXIT_FAILURE;
  }
  printf("System page size: %ld bytes\n", pagesize);

  // Map the CFG register
  uint32_t cfg_page_count = (CFG_SIZE - 1) / pagesize + 1; // Calculate number of pages needed for CFG
  cfg = mmap(NULL, cfg_page_count * pagesize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, AXI_CFG);
  if(cfg == MAP_FAILED) {
    perror("Failed to map CFG register");
    close(fd);
    return EXIT_FAILURE;
  }
  printf("CFG register mapped to address: %p\n", cfg);

  //////////////////// 2. Spawn Interrupt Detection Threads ////////////////////

  pthread_t interrupt_threads[8];

  // Spawn one thread per interrupt
  int interrupt_nums[8];
  for (int i = 0; i < 8; i++) {
    interrupt_nums[i] = i;
    if (pthread_create(&interrupt_threads[i], NULL, interrupt_thread_func, &interrupt_nums[i]) != 0) {
      fprintf(stderr, "Failed to create thread for interrupt %d\n", i);
    }
  }

  //////////////////// 3. Command Loop ////////////////////
  print_help(); // Print available commands
  while(1) {
    usleep(1000); // Sleep for 1 ms between commands
    printf("Enter command (or \"help\"): \n");
    char command[256]; // Buffer for user input
    char *num_endptr; // Pointer for strtoul, will mark the end of numerals
    fgets(command, sizeof(command), stdin); // Read user input string
    command[strcspn(command, "\n")] = 0; // Remove newline character
    char *token = strtok(command, " "); // Get the first token

    // No command entered
    if(token == NULL) continue;
    
    // Help command
    if(strcmp(token, "help") == 0) { 
      print_help();

    } else if(strcmp(token, "set") == 0) { // Set a single interrupt
      // 1st token is interrupt number
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify an interrupt number (0-7).\n"); continue; } // Check for interrupt number
      uint32_t interrupt_num = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
      if(num_endptr == token || interrupt_num > 7) { printf("Invalid interrupt number specified: %s\n", token); continue; } // Check for valid interrupt number
      // 2nd token is value (0 to disable, 1 to enable)
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify a value (0 to disable, 1 to enable).\n"); continue; } // Check for value
      uint32_t value = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
      if(num_endptr == token || (value != 0 && value != 1)) { printf("Invalid value specified: %s\n", token); continue; } // Check for valid value
      set_interrupt(cfg, interrupt_num, value); // Set the interrupt
    
    } else if(strcmp(token, "set_mask") == 0) { // Set multiple interrupts with an 8-bit mask to a value
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify an 8-bit mask (e.g., 0b00001111).\n"); continue; } // Check for mask
      uint32_t mask = strtoul(token, &num_endptr, 2); // Convert string to unsigned long in base 2
      if(num_endptr == token || mask > 0xFF) { printf("Invalid mask specified: %s\n", token); continue; } // Check for valid mask
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify a value (0 to disable, 1 to enable).\n"); continue; } // Check for value
      uint32_t value = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
      if(num_endptr == token || (value != 0 && value != 1)) { printf("Invalid value specified: %s\n", token); continue; } // Check for valid value
      set_interrupt_mask(cfg, (uint8_t)mask, value); // Set the interrupt mask with the specified value
    
    } else if(strcmp(token, "set_all") == 0) { // Set all interrupts to a single given bit
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify a value (0 to disable, 1 to enable).\n"); continue; } // Check for value
      uint32_t value = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
      if(num_endptr == token || (value != 0 && value != 1)) { printf("Invalid value specified: %s\n", token); continue; } // Check for valid value
      set_all_interrupts(cfg, value); // Set all interrupts to the given value

    } else if(strcmp(token, "hard_set") == 0) { // Hard set all interrupts to the given 8-bit value
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify an 8-bit value (e.g., 0b00001111).\n"); continue; } // Check for value
      uint32_t value = strtoul(token, &num_endptr, 2); // Convert string to unsigned long in base 2
      if(num_endptr == token || value > 0xFF) { printf("Invalid value specified: %s\n", token); continue; } // Check for valid value
      hard_set_all_interrupts(cfg, (uint8_t)value); // Hard set all interrupts to the given value

    } else if(strcmp(token, "clear") == 0) { // Clear a single interrupt
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify an interrupt number to clear (0-7).\n"); continue; } // Check for interrupt number
      uint32_t interrupt_num = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
      if(num_endptr == token || interrupt_num > 7) { printf("Invalid interrupt number specified: %s\n", token); continue; } // Check for valid interrupt number
      clear_interrupt(interrupt_num); // Clear the interrupt
      
    } else if(strcmp(token, "clear_mask") == 0) { // Clear multiple interrupts with an 8-bit mask
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify an 8-bit mask to clear (e.g., 0b00001111).\n"); continue; } // Check for mask
      uint32_t mask = strtoul(token, &num_endptr, 2); // Convert string to unsigned long in base 2
      if(num_endptr == token || mask > 0xFF) { printf("Invalid mask specified: %s\n", token); continue; } // Check for valid mask
      clear_interrupt_mask((uint8_t)mask); // Clear the interrupt mask

    } else if(strcmp(token, "clear_all") == 0) { // Clear all interrupts
      clear_all_interrupts(); // Clear all interrupts

    } else if(strcmp(token, "exit") == 0) { // Exit command
      break; // Exit the loop

    } else { // Unknown command
      printf("Unknown command: %s\n", token);
      print_help(); // Print help message
    }
  } // End of command loop
  
  // Cycle the interrupt bits twice to make sure all the interrupts are triggered
  printf("Cycling interrupt bits...\n");
  for (int j = 0; j < 2; j++) {
    set_interrupt_mask(cfg, 0xFF, 1); // Reset all interrupts
    usleep(1000); // Sleep for 1 ms
    set_interrupt_mask(cfg, 0xFF, 0); // Set all interrupts to stop the threads
    usleep(1000); // Sleep for 1 ms
  }

  // Join interrupt threads
  printf("Marking all interrupts as done...\n");
  for (int i = 0; i < 8; i++) {
    pthread_mutex_lock(&irq_mutexes[i]);
    irq_status[i] = 2; // Mark the interrupt as done
    pthread_mutex_unlock(&irq_mutexes[i]);
  }
  printf("Joining interrupt threads...\n");
  for (int i = 0; i < 8; i++) {
    pthread_join(interrupt_threads[i], NULL); // Wait for the thread to finish
    printf("Thread for interrupt %d joined.\n", i);
  }
  
  // Clear all interrupts
  printf("Clearing all interrupts...\n");
  clear_all_interrupts(); // Clear all interrupts to ensure no pending interrupts remain
  
  // Destroy mutexes
  printf("Destroying mutexes...\n");
  for (int i = 0; i < 8; i++) {
    pthread_mutex_destroy(&irq_mutexes[i]); // Destroy each mutex
  }

  // Unmap memory
  printf("Unmapping memory...\n");
  if(munmap((void *)cfg, cfg_page_count * pagesize) < 0) {
    perror("Failed to unmap CFG register");
  }
  close(fd);
  
  // Exit message
  printf("Exiting program.\n");

  return EXIT_SUCCESS;
}

/////////////////////// Functions ////////////////////

// Set a single interrupt
// interrupt_num: 0-7, value: 0 to disable, 1 to enable
void set_interrupt(volatile void *cfg, uint32_t interrupt_num, uint32_t value)
{
  if(interrupt_num > 7) {
    printf("Invalid interrupt number: %u. Must be between 0 and 7.\n", interrupt_num);
    return;
  }
  uint32_t *cfg_reg = (uint32_t *)cfg;
  // Interrupts are split across two 32-bit registers, with the first 4 interrupts in the first register and the next 4 in the second
  uint32_t shifted_interrupt_num = interrupt_num % 4; // Get the shifted interrupt number (0-3)
  if (shifted_interrupt_num != interrupt_num) {
    cfg_reg += 1; // Move to the next register if the interrupt number is 4 or greater
  }
  if(value) {
    *cfg_reg |= (1 << shifted_interrupt_num); // Set the bit to enable the interrupt
  } else {
    *cfg_reg &= ~(1 << shifted_interrupt_num); // Clear the bit to disable the interrupt
  }
  printf("Interrupt %u set to %u.\n", interrupt_num, value);
}

// Set multiple interrupts with an 8-bit mask to a value
void set_interrupt_mask(volatile void *cfg, uint8_t mask, uint32_t value)
{
  uint32_t *cfg_reg = (uint32_t *)cfg;
  // Check the first 4 bits of the mask. If nonzero, set the corresponding bits in the CFG register to the value
  if(mask & 0x0F) {
    if(value) {
      *cfg_reg |= (mask & 0x0F); // Set the bits to enable the interrupts
    } else {
      *cfg_reg &= ~(mask & 0x0F); // Clear the bits to disable the interrupts
    }
    printf("Interrupt mask set: 0b"BYTE_TO_BINARY_PATTERN" to %u.\n", BYTE_TO_BINARY(mask & 0x0F), value);
  }
  // Check the next 4 bits of the mask. If nonzero, set the corresponding bits in the CFG register to the value
  if(mask & 0xF0) {
    if(value) {
      *(cfg_reg + 1) |= (mask & 0xF0 >> 4); // Set the bits to enable the interrupts
    } else {
      *(cfg_reg + 1) &= ~(mask & 0xF0 >> 4); // Clear the bits to disable the interrupts
    }
    printf("Interrupt mask set: 0b"BYTE_TO_BINARY_PATTERN" to %u.\n", BYTE_TO_BINARY(mask & 0xF0), value);
  }
}

// Hard set all interrupts to the given 8-bit value
void hard_set_all_interrupts(volatile void *cfg, uint8_t value)
{
  uint32_t *cfg_reg = (uint32_t *)cfg;
  // Set the first 4 bits of the CFG register to the value
  *cfg_reg = (value & 0x0F); // Set the first 4 bits
  // Set the next 4 bits of the next CFG register to the value
  *(cfg_reg + 1) = (value & 0xF0) >> 4; // Set the next 4 bits
  printf("All interrupts hard set to: 0x%02X.\n", value);
}

// Clear a single interrupt (on the PS side)
void clear_interrupt(uint32_t interrupt_num)
{
  // validate the interrupt number
  if(interrupt_num > 7) {
    printf("Invalid interrupt number: %u. Must be between 0 and 7.\n", interrupt_num);
    return;
  }

  // Try to lock the mutex for this interrupt
  if(pthread_mutex_trylock(&irq_mutexes[interrupt_num]) != 0) {
    printf("Interrupt %u hasn't been set, can't be cleared.\n", interrupt_num);
    return; // If the mutex is already locked, skip clearing this interrupt
  }

  // Check if the interrupt is pending
  if(irq_status[interrupt_num] == 0) {
    printf("Interrupt %u is not pending, nothing to clear.\n", interrupt_num);
    pthread_mutex_unlock(&irq_mutexes[interrupt_num]); // Unlock the mutex before returning
    return; // If not pending, nothing to clear
  }

  // Open the device file /dev/uio[interrupt_num]
  char uio_path[32];
  snprintf(uio_path, sizeof(uio_path), "/dev/uio%u", interrupt_num);
  int fd = open(uio_path, O_RDWR);
  if(fd < 0) {
    fprintf(stderr, "Failed to open UIO device file for interrupt %u: ", interrupt_num);
    perror("Failed to open UIO device file");
    pthread_mutex_unlock(&irq_mutexes[interrupt_num]); // Unlock the mutex before returning
    return;
  }

  // Clear the interrupt by writing to the UIO device
  uint32_t clear_value = 1;
  if(write(fd, &clear_value, sizeof(clear_value)) < 0) {
    fprintf(stderr, "Failed to clear interrupt %u: ", interrupt_num);
    perror("Failed to write to UIO device");
  } else {
    printf("Interrupt %u cleared.\n", interrupt_num);
  }
  close(fd);

  // Mark the interrupt as not pending
  irq_status[interrupt_num] = 0; // Reset the status to not pending
  // Unlock the mutex after clearing
  pthread_mutex_unlock(&irq_mutexes[interrupt_num]);
}

// Clear multiple interrupts with an 8-bit mask (on the PS side)
void clear_interrupt_mask(uint8_t mask)
{
  // Open and clean each UIO device corresponding to the mask
  for(uint32_t i = 0; i < 8; i++) {
    if(mask & (1 << i)) { // Check if the i-th bit is set in the mask
      clear_interrupt(i); // Clear the interrupt for this bit
    }
  }
  printf("Interrupt mask cleared: 0x%02X\n", mask);
}

// Clear all interrupts (on the PS side)
void clear_all_interrupts()
{
  printf("Clearing all interrupts...\n");
  for(uint32_t i = 0; i < 8; i++) {
    clear_interrupt(i); // Clear each interrupt from 0 to 7
  }
  printf("All interrupts cleared.\n");
}

// Thread function to handle interrupt detection
void *interrupt_thread_func(void *arg) {
  int interrupt_num = *(int *)arg;
  char uio_path[32];
  snprintf(uio_path, sizeof(uio_path), "/dev/uio%d", interrupt_num);
  
  while(1) {
    // Lock the mutex for this interrupt
    pthread_mutex_lock(&irq_mutexes[interrupt_num]);
    
    // Check if the interrupt is pending
    if (irq_status[interrupt_num] == 0) {
      // If pending, wait for the interrupt
      
      // Open the UIO device file for this interrupt
      int fd = open(uio_path, O_RDWR);
      if (fd < 0) {
        perror("Failed to open UIO device file");
        pthread_exit(NULL);
      }
      
      // Wait for interrupt (blocking read)
      unsigned int irq = 0;
      if (read(fd, &irq, sizeof(irq)) <= 0) {
        perror("Failed to read interrupt");
        break;
      }
      
      // Mark the interrupt as received
      irq_status[interrupt_num] = 1;
      close(fd); // Close the UIO device file
      printf("Interrupt %d received!\n", interrupt_num);

      // Unlock the mutex after processing
      pthread_mutex_unlock(&irq_mutexes[interrupt_num]);
    } else {
      if (irq_status[interrupt_num] == 2) {
        // This means the interrupt is done
        printf("Interrupt %d processing done.\n", interrupt_num);
        pthread_mutex_unlock(&irq_mutexes[interrupt_num]);
        break; // Exit the thread if processing is done
      }
      else {
        pthread_mutex_unlock(&irq_mutexes[interrupt_num]);
      }
    }
    
    // Sleep for a short duration to avoid busy waiting
    usleep(1000); // Sleep for 1 ms
  }
}

// Print out the available commands
void print_help()
{
  printf("\n");
  printf("---------------------\n");
  printf("Interrupt Test Program\n");
  printf("---------------------\n");
  printf("\n");
  printf("This program allows you to test and control PS/PL interrupts.\n");
  printf("You can set, clear, and hard set interrupts, as well as view their status.\n");
  printf("\n");
  printf("The interrupts are triggerd based off of the two pairs of 4 bits in different 32-bit registers.\n");
  printf("The first 4 bits control interrupts 0-3, and the next 4 bits control interrupts 4-7.\n");
  printf("In each of the registers, the polarity and trigger style of the interrupts are different between bits,\n");
  printf("but the same as the corresponding bits in the other register.\n");
  printf("Interrupts 0, 1, 4, and 5 are active high, edge triggered,\n");
  printf("while interrupts 2, 3, 6, and 7 are active high, level triggered.\n");
  printf("\n");
  printf("Experiment!\n");
  printf("\n");
  printf("---------------------\n");
  printf("Available commands:\n");
  printf("---------------------\n");
  printf("help - Show this help message\n");
  printf("set <interrupt_num> <value> - Set a single interrupt (0-7, value: 0 to disable, 1 to enable)\n");
  printf("set_mask <mask> <value> - Set multiple interrupts with an 8-bit binary mask (e.g., 00001111) all to the given value\n");
  printf("set_all <value> - Set all interrupts to the given value (0 to disable, 1 to enable)\n");
  printf("hard_set <value> - Hard set all interrupts to the given 8-bit binary value (e.g., 00001111)\n");
  printf("clear <interrupt_num> - Clear (on the PS side) a single interrupt (0-7)\n");
  printf("clear_mask <mask> - Clear (on the PS side) multiple interrupts with an 8-bit binary mask\n");
  printf("clear_all - Clear (on the PS side) all interrupts\n");
  printf("exit - Exit the program\n");
  printf("---------------------\n");
  printf("\n");
}
