#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/ioctl.h>

#define CMA_ALLOC _IOWR('Z', 0, uint32_t)

#define AXI_HUB_BASE  0x40000000
#define AXI_HUB_CFG   0x00000000
#define AXI_HUB_STS   0x01000000

uint8_t nand_8bit(uint8_t a, uint8_t b, volatile void *cfg, volatile void *sts)
{
  // Concatenate two 8-bit values into a 32-bit data word
  uint16_t data = (a << 8) | b;

  // Write the data word to the CFG register
  *((uint16_t *)cfg) = data;

  // Read the data word from the STS register
  return *((uint8_t *)sts);
}

int main()
{
  int fd, i; // File descriptor, loop counter
  volatile void *cfg; // CFG register in AXI hub (set to 16 bits)
  volatile void *sts; // STS register in AXI hub (set to 8 bits)

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
  cfg = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_HUB_BASE | AXI_HUB_CFG);
  sts = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_HUB_BASE | AXI_HUB_STS);

  close(fd);
  printf("Mapping complete.\n");

  // Perform NAND operation on two 8-bit values
  printf("Performing NAND operation...\n");
  uint8_t a = 0b10101010;
  uint8_t b = 0b11001100;
  uint8_t result = nand_8bit(a, b, cfg, sts);
  uint8_t expected = ~(a & b);

  printf("NAND(%02x, %02x) = %02x (expected %02x)\n", a, b, result, expected);
}
