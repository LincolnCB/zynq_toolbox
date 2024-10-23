#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <string.h>
#include <inttypes.h>

#define CMA_ALLOC _IOWR('Z', 0, uint32_t)

#define AXI_HUB_BASE                  0x40000000
#define AXI_HUB_CFG     AXI_HUB_BASE + 0x0000000
#define AXI_HUB_STS     AXI_HUB_BASE + 0x1000000
#define AXI_HUB_0_FIFO  AXI_HUB_BASE + 0x2000000
#define AXI_HUB_1_BRAM  AXI_HUB_BASE + 0x3000000

#define BRAM_MAX_ADDR   (uint32_t) 16384 // 16KiB of BRAM, 32-bit words

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
  printf("      (address is in units of 32-bit words. Range: 0-"PRIu32")\n", BRAM_MAX_ADDR - 1);
  printf("  bread <addr>\n");
  printf("    - Read from BRAM at address <addr>\n");
  printf("      (address is in units of 32-bit words. Range: 0-"PRIu32")\n", BRAM_MAX_ADDR - 1);
  printf("  exit\n");
  printf("    - Exit the program\n");
}

int main()
{
  int fd, i; // File descriptor, loop counter
  volatile void *cfg; // CFG register in AXI hub (set to 32 bits wide)
  volatile void *sts; // STS register in AXI hub (set to 32 bits wide)
  volatile void *fifo; // FIFO register in AXI hub on port 0
  volatile void *bram; // BRAM register in AXI hub on port 1

  printf("Test program for Pavel Demin's AXI hub\n");
  printf("Setup:\n");

  // Open /dev/mem to access physical memory
  printf("Opening /dev/mem...\n");
  if((fd = open("/dev/mem", O_RDWR)) < 0)
  {
    perror("open");
    return EXIT_FAILURE;
  }

  // Map CFG and STS registers
  // The base address of the AXI hub is 0x40000000
  // Bits 24-26 are used to indicate the target in the hub
  // 0 is the CFG register and 1 is the STS register
  // 2-7 are ports 0-5 (n-2)
  printf("Mapping CFG and STS registers...\n");
  cfg = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_HUB_CFG);
  printf("CFG register mapped to %x\n", AXI_HUB_CFG);
  sts = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_HUB_STS);
  printf("STS register mapped to %x\n", AXI_HUB_STS);
  fifo = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_HUB_0_FIFO);
  printf("FIFO (port 0) mapped to %x\n", AXI_HUB_0_FIFO);
  bram = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_HUB_1_BRAM);
  printf("BRAM (port 1) mapped to %x\n", AXI_HUB_1_BRAM);
  
  close(fd);
  printf("Mapping complete.\n");

  // Main command loop
  print_help();
  while(1){
    printf("Enter command: ");

    // Read command from user input
    char command[256];
    fgets(command, sizeof(command), stdin);
    command[strcspn(command, "\n")] = 0; // Remove newline character
    char *token = strtok(command, " ");

    if(token == NULL) continue; // No command entered

    if(strcmp(token, "help") == 0) { // Help command
      print_help();

    } else if(strcmp(token, "freset") == 0) { // FIFO reset command
      *((volatile uint32_t *)cfg) |=  0b1; // Reset the FIFO
      *((volatile uint32_t *)cfg) &= ~0b1; // Clear the reset
      printf("FIFO reset.\n");

    } else if(strcmp(token, "fstatus") == 0) { // FIFO status command
      print_fifo_status(sts);

    } else if(strcmp(token, "fread") == 0) { // FIFO read command
      token = strtok(NULL, " ");
      if(token != NULL) {
        int num = atoi(token);
        for(i = 0; i < num; i++) { // Read specified number of words
          uint32_t value = *((volatile uint32_t *)fifo);
          printf("Read value: %u\n", value);
        }
      } else { // No number specified
        printf("Please specify the number of words to read.\n");
      }

    } else if(strcmp(token, "fwrite") == 0) { // FIFO write command
      token = strtok(NULL, " ");
      if(token != NULL) { // Check for value
        uint32_t value = atoi(token);
        token = strtok(NULL, " ");
        if(token != NULL) { // Check for increment number
          int incr_num = atoi(token);
          for(i = 0; i < incr_num; i++) { // Write repeatedly incremented values
            *((volatile uint32_t *)fifo) = value + i;
            printf("Wrote value: %u\n", value + i);
          }
        } else { // Write a single value
          *((volatile uint32_t *)fifo) = value;
          printf("Wrote value: %u\n", value);
        }
      } else { // No value specified
        printf("Please specify a value to write.\n");
      }

    } else if(strcmp(token, "bwrite") == 0) { // BRAM write command
      token = strtok(NULL, " ");
      if(token != NULL) { // Check for address
        uint32_t addr = atoi(token);
        if (addr < BRAM_MAX_ADDR) { // Check for valid address range
          token = strtok(NULL, " ");
          if(token != NULL) { // Check for value
            uint32_t value = atoi(token);
            *((volatile uint32_t *)(bram + (addr * sizeof(uint32_t)))) = value; // Write value to BRAM
            printf("Wrote value %u to BRAM address %u.\n", value, addr);
          } else { // No value specified
            printf("Please specify a value to write to BRAM.\n");
          }
        } else { // Invalid address
          printf("Invalid address. Please specify an address between 0 and "PRIu32".\n", BRAM_MAX_ADDR - 1);
        }
      } else { // No address specified
        printf("Please specify an address to write to.\n");
      }

    } else if(strcmp(token, "bread") == 0) { // BRAM read command
      token = strtok(NULL, " ");
      if(token != NULL) { // Check for address
        uint32_t addr = atoi(token);
        uint32_t value = *((volatile uint32_t *)(bram + (addr * sizeof(uint32_t)))); // Read value from BRAM
        printf("Read value %u from BRAM address %u.\n", value, addr);
      } else { // No address specified
        printf("Please specify an address to read from.\n");
      }

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
