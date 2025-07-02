#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <inttypes.h>

#define CMA_ALLOC _IOWR('Z', 0, uint32_t)

// Addresses are defined in the hardware design Tcl file
#define AXI_CFG 0x40000000
#define AXI_STS 0x41000000

void test_write_8(volatile void *cfg, uint32_t offset, uint8_t value) {
  *((uint64_t *)(cfg)) = 0xffffffffffffffff; // pre-set the register
  printf("Initialized to: 0x%08x%08x\n", *((uint32_t *)(cfg + 4)), *((uint32_t *)(cfg)));
  printf("Writing 8-bit value 0x%02x to offset +%d\n", value, offset);
  *((uint8_t *)(cfg + offset)) = value;
  printf("Full register:  0x%08x%08x\n", *((uint32_t *)(cfg + 4)), *((uint32_t *)(cfg)));
}

void test_write_16(volatile void *cfg, uint32_t offset, uint16_t value) {
  *((uint64_t *)(cfg)) = 0xffffffffffffffff; // pre-set the register
  printf("Initialized to: 0x%08x%08x\n", *((uint32_t *)(cfg + 4)), *((uint32_t *)(cfg)));
  printf("Writing 16-bit value 0x%04x to offset +%d\n", value, offset);
  *((uint16_t *)(cfg + offset)) = value;
  printf("Full register:  0x%08x%08x\n", *((uint32_t *)(cfg + 4)), *((uint32_t *)(cfg)));
}

void test_write_32(volatile void *cfg, uint32_t offset, uint32_t value) {
  *((uint64_t *)(cfg)) = 0xffffffffffffffff; // pre-set the register
  printf("Initialized to: 0x%08x%08x\n", *((uint32_t *)(cfg + 4)), *((uint32_t *)(cfg)));
  printf("Writing 32-bit value 0x%08x to offset +%d\n", value, offset);
  *((uint32_t *)(cfg + offset)) = value;
  printf("Full register:  0x%08x%08x\n", *((uint32_t *)(cfg + 4)), *((uint32_t *)(cfg)));
}

uint32_t nand_32bit_64bit_write(uint32_t a, uint32_t b, volatile void *cfg, volatile void *sts)
{
  // Concatenate two 32-bit values into a 64-bit data word
  uint64_t data = (((uint64_t) a)<< 32) | (uint64_t) b;

  // Write the 64-bit data word to the CFG register
  *((uint64_t *)cfg) = data;
  printf("Wrote 0x%016"PRIx64" to CFG register\n", data);

  // Read the data word from the STS register
  return *((uint32_t *)sts);
}

uint32_t nand_32bit_32bit_write(uint32_t a, uint32_t b, volatile void *cfg, volatile void *sts)
{
  // Write the first 32-bit data word to the CFG register
  *((uint32_t *)(cfg + 0)) = a;
  printf("Wrote 0x%08"PRIx32" to first 32 bits of CFG register\n", a);

  // Write the second 32-bit data word to the CFG register
  *((uint32_t *)(cfg + 4)) = b;
  printf("Wrote 0x%08"PRIx32" to second 32 bits of CFG register\n", b);

  // Read the data word from the STS register
  return *((uint32_t *)sts);
}

int main()
{
  int fd, i; // File descriptor, loop counter
  volatile void *cfg; // CFG register AXI interface (using the first 64 bits)
  volatile void *sts; // STS register AXI interface (using the first 32 bits)

  // Open /dev/mem to access physical memory
  printf("Opening /dev/mem...\n");
  if((fd = open("/dev/mem", O_RDWR)) < 0)
  {
    perror("open");
    return EXIT_FAILURE;
  }

  // Map CFG and STS registers
  // Addresses are defined in the hardware design Tcl file
  // sysconf(_SC_PAGESIZE) is the minimum size to map, as it's the size of a memory page
  printf("Mapping CFG and STS registers...\n");
  cfg = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_CFG);
  printf("CFG register mapped to %08"PRIx32"\n", AXI_CFG);
  sts = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, AXI_STS);
  printf("STS register mapped to %08"PRIx32"\n", AXI_STS);

  close(fd);
  printf("Mapping complete.\n");


  // Do some example writes and reads
  printf("\nExample writes\n");
  printf("\n---- 8-bit writes ----\n");
  for (i = 0; i < 5; i++) {
    test_write_8(cfg, i, 0x12);
    printf("----\n");
  }
  printf("\n---- 16-bit writes ----\n");
  for (i = 0; i < 5; i++) {
    test_write_16(cfg, i, 0x1234);
    printf("----\n");
  }
  printf("\n---- 32-bit writes ----\n");
  for (i = 0; i < 5; i++) {
    test_write_32(cfg, i, 0x12345678);
    printf("----\n");
  }
  printf("\nExample reads...\n");
  printf("Writing 64-bit value 0x123456789abcdef0 to full register...\n");
  *((uint64_t *)cfg) = 0x123456789ABCDEF0;
  printf("Full register: 0x%08x%08x\n", *((uint32_t *)(cfg + 4)), *((uint32_t *)(cfg)));
  for (int i = 0; i < 8; i++) {
    printf("8-bit read from offset +%d: 0x%02"PRIx8"\n", i, *((uint8_t *)(cfg + i)));
  }
  printf("----\n");
  for (int i = 0; i < 7; i++) {
    printf("16-bit read from offset +%d: 0x%04"PRIx16"\n", i, *((uint16_t *)(cfg + i)));
  }
  printf("----\n");
  for (int i = 0; i < 5; i++) {
    printf("32-bit read from offset +%d: 0x%08"PRIx32"\n", i, *((uint32_t *)(cfg + i)));
  }

  // Perform NAND operation on two 32-bit values by writing them individually
  uint32_t a = 0x12345678;
  uint32_t b = 0x87654321;
  uint32_t expected = ~(a & b);

  printf("\nPerforming NAND operation from CFG to STS by writing CFG in two 32-bit writes...\n");
  uint32_t result = nand_32bit_32bit_write(a, b, cfg, sts);
  printf("NAND(0x%08"PRIx32", 0x%08"PRIx32") = 0x%08"PRIx32" (expected 0x%08"PRIx32")\n", a, b, result, expected);
  if (result == expected) printf("32-bit-write NAND operation successful!\n");
  else printf("32-bit-write NAND operation failed :(\n");

  // Perform NAND operation on two 32-bit values
  a = 0xABCDEF01;
  b = 0x01234567;
  expected = ~(a & b);

  printf("\nPerforming NAND operation from CFG to STS in one 64-bit write...\n");
  result = nand_32bit_64bit_write(a, b, cfg, sts);
  printf("NAND(0x%08"PRIx32", 0x%08"PRIx32") = 0x%08"PRIx32" (expected 0x%08"PRIx32")\n", a, b, result, expected);
  if (result == expected) printf("64-bit-write NAND operation successful!\n");
  else printf("64-bit-write NAND operation failed :(\n");

}
