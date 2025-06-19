#include <fcntl.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

//////////////////// Mapped Memory Definitions ////////////////////

#define CMA_ALLOC _IOWR('Z', 0, uint32_t)

// Addresses are defined in the hardware design TCL file
#define AXI_CFG  (uint32_t) 0x40000000
#define AXI_STS  (uint32_t) 0x41000000
#define AXI_FIFO (uint32_t) 0x42000000
#define AXI_BRAM (uint32_t) 0x43000000

#define CFG_SIZE        (uint32_t) 96 / 8 // Size of the configuration register in bytes
#define STS_SIZE        (uint32_t) 64 / 8 // Size of the status register in bytes

// FIFO doesn't need a size definition since it is a stream

#define BRAM_DEPTH      (uint32_t) 16384 // 16KiB of BRAM, 32-bit words
#define BRAM_SIZE       (uint32_t) (BRAM_DEPTH * 32 / 8) // Size of BRAM in bytes



//////////////////// Function Prototypes ////////////////////

// Get the write count from the status register
uint32_t wr_count(volatile void *sts);
// Get the FULL flag from the status register
uint32_t is_full(volatile void *sts);
// Get the OVERFLOW flag from the status register
uint32_t is_overflow(volatile void *sts);
// Get the read count from the status register
uint32_t rd_count(volatile void *sts);
// Get the EMPTY flag from the status register
uint32_t is_empty(volatile void *sts);
// Get the UNDERFLOW flag from the status register
uint32_t is_underflow(volatile void *sts);
// Print out the full status of the FIFO
void print_fifo_status(volatile void *sts);
// Print out the available commands
void print_help();



//////////////////// Main ////////////////////
int main()
{
  
  //////////////////// 1. Setup ////////////////////
  printf("Test program for AXI FIFO and BRAM interfaces\n");
  printf("Setup:\n");

  int fd, i; // File descriptor, loop counter
  volatile void *cfg; // CFG register AXI interface
  volatile void *sts; // STS register AXI interface
  volatile void *fifo; // FIFO AXI interface
  volatile void *bram; // BRAM AXI interface

  uint32_t pagesize = sysconf(_SC_PAGESIZE); // Get the system page size
  printf("System page size: %d\n", pagesize);

  // Open /dev/mem to access physical memory
  printf("Opening /dev/mem...\n");
  if((fd = open("/dev/mem", O_RDWR)) < 0)
  {
    perror("open");
    return EXIT_FAILURE;
  }

  // Map CFG and STS registers
  // Addresses are defined in the hardware design TCL file
  printf("Mapping registers and ports...\n");

  // CFG register
  uint32_t cfg_page_count = (CFG_SIZE - 1) / pagesize + 1; // Calculate number of pages needed for CFG
  cfg = mmap(NULL, cfg_page_count * pagesize, PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_CFG);
  printf("CFG register mapped to 0x%x:0x%x (%d pages)\n", AXI_CFG, AXI_CFG + CFG_SIZE - 1, cfg_page_count);

  // STS register
  uint32_t sts_page_count = (STS_SIZE - 1) / pagesize + 1; // Calculate number of pages needed for STS
  sts = mmap(NULL, sts_page_count * pagesize, PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_STS);
  printf("STS register mapped to 0x%x:0x%x (%d pages)\n", AXI_STS, AXI_STS + STS_SIZE - 1, sts_page_count);

  // FIFO on port 0
  // FIFO is only one page because it's a stream
  fifo = mmap(NULL, pagesize, PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_FIFO);
  printf("FIFO (port 0) mapped to 0x%x\n", AXI_FIFO);

  // BRAM on port 1
  uint32_t bram_page_count = (BRAM_SIZE - 1) / pagesize + 1; // Calculate number of pages needed for BRAM
  bram = mmap(NULL, bram_page_count * pagesize, PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_BRAM);
  printf("BRAM (port 1) mapped to 0x%x:0x%x (%d pages)\n", AXI_BRAM, AXI_BRAM + BRAM_SIZE - 1, bram_page_count);
  
  // File can be closed after mapping without affecting the mapped memory
  close(fd);
  printf("Mapping complete.\n");



  //////////////////// 2. Compatibility with other software examples ////////////////////

  // CFG bits 63:0 and STS bits 31:0 are used for the reg_test NAND example
  cfg = cfg + 8; // Skip the first 8 bytes of the CFG register
  sts = sts + 4; // Skip the first 4 bytes of the STS register


  //////////////////// 3. Main command loop ////////////////////
  print_help();
  while(1){
    printf("Enter command: ");

    // Read command from user input
    char command[256];
    char *num_endptr; // Pointer for strtoul, will mark the end of numerals
    fgets(command, sizeof(command), stdin); // Read user input string
    command[strcspn(command, "\n")] = 0; // Remove newline character
    char *token = strtok(command, " "); // Get the first token

    // No command entered
    if(token == NULL) continue;

    // Help command
    if(strcmp(token, "help") == 0) { 
      print_help();

    // FIFO reset command
    } else if(strcmp(token, "freset") == 0) {
      *((volatile uint32_t *)cfg) |=  0b1; // Reset the FIFO
      usleep(10); // Wait for a short time to ensure the reset is applied
      *((volatile uint32_t *)cfg) &= ~0b1; // Clear the reset
      printf("FIFO reset.\n");

    // FIFO status command
    } else if(strcmp(token, "fstatus") == 0) {
      print_fifo_status(sts);

    // FIFO read command
    } else if(strcmp(token, "fread") == 0) {
      // 1st token is number of words to read
      token = strtok(NULL, " "); // strtok keeps track of the last stream pointer passed in if NULL is passed
      if(token == NULL) { printf("Please specify the number of words to read.\n"); continue; } // Check for number
      int num = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
      if(num_endptr == token) { printf("Invalid number specified: %s\n", token); continue; } // Check for valid number
      printf("Reading %d words from FIFO...\n", num);
      for(i = 0; i < num; i++) { // Read specified number of words
        uint32_t value = *((volatile uint32_t *)fifo);
        printf("Read value: %u\n", value);
      }

    // FIFO write command
    } else if(strcmp(token, "fwrite") == 0) {
      // 1st token is value
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify a value to write.\n"); continue; } // Check for value
      uint32_t value = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
      if(num_endptr == token) { printf("Invalid value specified: %s\n", token); continue; } // Check for valid value
      // 2nd token is increment number
      token = strtok(NULL, " ");
      if(token == NULL) { // Write a single value if no increment number is specified
        *((volatile uint32_t *)fifo) = value;
        printf("Wrote value: %u\n", value);
      } else { // Write repeatedly incremeted values otherwise
        uint32_t incr_num = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
        if(num_endptr == token) { printf("Invalid increment number specified: %s\n", token); continue; } // Check for valid increment number
        for(i = 0; i < incr_num; i++) { // Write repeatedly incremented values
          *((volatile uint32_t *)fifo) = value + i;
          printf("Wrote value: %u\n", value + i);
        }
      }

    // BRAM write command
    } else if(strcmp(token, "bwrite") == 0) {
      // 1st token is address
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify an address to write to.\n"); continue; } // Check for address
      uint32_t addr = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
      if(num_endptr == token) { printf("Invalid address specified: %s\n", token); continue; } // Check for valid address
      if (addr >= BRAM_SIZE) { // Check for valid address range
        printf("Invalid address. Please specify an address between 0 and %"PRIu32".\n", BRAM_SIZE - 1); 
        continue; 
      }
      // 2nd token is value
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify a value to write to BRAM.\n"); continue; } // Check for value
      uint32_t value = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
      if(num_endptr == token) { printf("Invalid value specified: %s\n", token); continue; } // Check for valid value
      *((volatile uint32_t *)(bram + addr)) = value; // Write value to BRAM
      printf("Wrote value %u to BRAM address %u.\n", value, addr);

    // BRAM read command
    } else if(strcmp(token, "bread") == 0) {
      // 1st token is address
      token = strtok(NULL, " ");
      if(token == NULL) { printf("Please specify an address to read from.\n"); continue; } // Check for address
      uint32_t addr = strtoul(token, &num_endptr, 10); // Convert string to unsigned long
      if(num_endptr == token) { printf("Invalid address specified: %s\n", token); continue; } // Check for valid address
      if (addr >= BRAM_SIZE) { // Check for valid address range
        printf("Invalid address. Please specify an address between 0 and %"PRIu32".\n", BRAM_SIZE - 1); 
        continue; 
      }
      uint32_t value = *((volatile uint32_t *)(bram + addr)); // Read value from BRAM
      printf("Read value %u from BRAM address %u.\n", value, addr);

    } else if(strcmp(token, "exit") == 0) { // Exit command
      break; // Exit the loop

    } else { // Unknown command
      printf("Unknown command: %s\n", token);
      print_help(); // Print help message
    }
  } // End of command loop

  // Unmap memory
  printf("Unmapping memory...\n");
  munmap((void *)cfg, sysconf(_SC_PAGESIZE));
  munmap((void *)sts, sysconf(_SC_PAGESIZE));
  munmap((void *)fifo, sysconf(_SC_PAGESIZE));
  munmap((void *)bram, sysconf(_SC_PAGESIZE));

  printf("Exiting program.\n");
}



//////////////////// Functions ////////////////////

// Get the write count from the status register
uint32_t wr_count(volatile void *sts)
{
  return *((volatile uint32_t *)sts) & 0b11111;
}

// Get the FULL flag from the status register
uint32_t is_full(volatile void *sts)
{
  return (*((volatile uint32_t *)sts) >> 5) & 0b1;
}

// Get the OVERFLOW flag from the status register
uint32_t is_overflow(volatile void *sts)
{
  return (*((volatile uint32_t *)sts) >> 6) & 0b1;
}

// Get the read count from the status register
uint32_t rd_count(volatile void *sts)
{
  return (*((volatile uint32_t *)sts) >> 7) & 0b11111;
}

// Get the EMPTY flag from the status register
uint32_t is_empty(volatile void *sts)
{
  return (*((volatile uint32_t *)sts) >> 12) & 0b1;
}

// Get the UNDERFLOW flag from the status register
uint32_t is_underflow(volatile void *sts)
{
  return (*((volatile uint32_t *)sts) >> 13) & 0b1;
}

// Print out the full status of the FIFO
void print_fifo_status(volatile void *sts)
{
  printf("FIFO Status:\n");
  printf(" Note: Write and Read counts will be the same for a synchronous FIFO\n");
  printf("  Write Count: %d\n", wr_count(sts));
  printf("  Read Count: %d\n", rd_count(sts));
  printf("  Full: %d\n", is_full(sts));
  printf("  Overflow: %d\n", is_overflow(sts));
  printf("  Empty: %d\n", is_empty(sts));
  printf("  Underflow: %d\n", is_underflow(sts));
}

// Print out the available commands
void print_help()
{
  printf("Operations: <required> [optional]\n");
  printf("  help\n");
  printf("    - Print this help message\n");
  printf("  freset\n");
  printf("    - Reset the FIFO\n");
  printf("  fstatus\n");
  printf("    - Print the FIFO status\n");
  printf("  fread <num>\n");
  printf("    - Read <num> 32-bit words from the FIFO\n");
  printf("  fwrite <val> [incr_num]\n");
  printf("    - Write <val> to the FIFO. Optionally repeatedly increment and write [incr_num] times\n");
  printf("  bwrite <addr> <val>\n");
  printf("    - Write <val> to BRAM at address <addr>\n");
  printf("      (address is in bytes: Range: 0-%"PRIu32")\n", BRAM_SIZE - 1);
  printf("  bread <addr>\n");
  printf("    - Read from BRAM at address <addr>\n");
  printf("      (address is in bytes: Range: 0-%"PRIu32")\n", BRAM_SIZE - 1);
  printf("  exit\n");
  printf("    - Exit the program\n");
}
