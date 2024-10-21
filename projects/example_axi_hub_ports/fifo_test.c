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
#define AXI_HUB_FIFO_0  AXI_HUB_BASE + 0x2000000

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

int main(int argc, char* argv[])
{
  int fd, i; // File descriptor, loop counter
  volatile void *cfg; // CFG register in AXI hub (set to 32 bits wide)
  volatile void *sts; // STS register in AXI hub (set to 32 bits wide)
  volatile void *fifo_0; // FIFO register in AXI hub on port 0

  // Check if the correct number of arguments is provided
  if (!((argc == 2 && strcmp(argv[1], "reset") == 0) || // Reset operation
        (argc == 3 && strcmp(argv[1], "read") == 0)  || // Read operation
        (argc == 4 && strcmp(argv[1], "write") == 0))) // Write operation
  {
    printf("Usage options:\n");
    printf("-   %s reset\n", argv[0]);
    printf("-   %s read <number_of_reads>\n", argv[0]);
    printf("-   %s write <write_start> <number_of_writes>\n", argv[0]);
    return EXIT_FAILURE;
  }

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
  printf("Mapping CFG and STS registers...\n");
  cfg = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_HUB_CFG);
  printf("CFG register mapped to %x\n", AXI_HUB_CFG);
  sts = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_HUB_STS);
  printf("STS register mapped to %x\n", AXI_HUB_STS);
  fifo_0 = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_HUB_FIFO_0);
  printf("FIFO register mapped to %x\n", AXI_HUB_FIFO_0);

  close(fd);
  printf("Mapping complete.\n");

  // Determine operation mode
  if (strcmp(argv[1], "reset") == 0) // Reset operation
  {
    printf("Resetting FIFO...\n");
    *((volatile uint32_t *)cfg) |=  0b1; // Reset FIFO
    *((volatile uint32_t *)cfg) &= ~0b1; // Clear Reset
  }
  else if (strcmp(argv[1], "read") == 0) // Read operation
  {
    int read_num = atoi(argv[2]);

    // Read N 32-bit words from the FIFO
    printf("Reading %d lines from FIFO...\n", read_num);
    for(i = 0; i < read_num; i++)
    {
      uint32_t data = *((volatile uint32_t *)fifo_0); // Read from FIFO
      printf("Read %d from FIFO\n", data);
    }
  }
  else if (strcmp(argv[1], "write") == 0) // Write operation
  {
    int start_val = atoi(argv[2]);
    int write_num = atoi(argv[3]);

    // Write N 32-bit words to the FIFO
    printf("Writing %d integers starting from %d to FIFO...\n", write_num, start_val);
    for(i = 0; i < write_num; i++)
    {
      *((volatile uint32_t *)fifo_0) = i + start_val; // Write to FIFO
      printf("Wrote %d to FIFO\n", i + start_val);
    }
  }

  // Print out the FIFO status
  printf("Checking FIFO status...\n");
  print_fifo_status(sts);
}
