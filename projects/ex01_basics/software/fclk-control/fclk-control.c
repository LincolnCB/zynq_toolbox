#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

// System Level Control Registers for clock control
#define SLCR_BASE 0xF8000000
// Define 32-bit register offsets by the byte offset and dividing by 4
#define SLCR_LOCK_REG_OFFSET 0x4 / 4
#define SLCR_UNLOCK_REG_OFFSET 0x8 / 4
#define FCLK0_CTRL_REG_OFFSET 0x170 / 4

// Bitmask lock/unlock codes
#define SLCR_LOCK_CODE 0x767B
#define SLCR_UNLOCK_CODE 0xDF0D

// Bitmasks for FCLK0 control register
// 25:20 - Divisor 1 (second stage divisor)
// 13: 8 - Divisor 0 (first stage divisor)
//  5: 4 - Clock source select (0x for IO PLL, 10 for ARM PLL, 11 for DDR PLL)
// All others reserved
#define FCLK0_UNRESERVED_MASK 0x03F03F30
#define FCLK0_DIVISOR_MAX     0b111111 // 63, 0x3F, 6 bits

// System Level Control Registers -- each is 32 bits, so the pointer is uint32_t
static volatile uint32_t *slcr;
static volatile uint32_t *slcr_unlock, *slcr_lock, *fclk0_ctrl;

void set_fclk0(uint32_t div0, uint32_t div1)
{
  // Unlock the SLCR registers
  *slcr_unlock = SLCR_UNLOCK_CODE;
  // Set the FCLK0 to 10 MHz
  *fclk0_ctrl = *fclk0_ctrl & ~FCLK0_UNRESERVED_MASK \
    | (div1 << 20) \
    | (div0 <<  8);
  // Lock the SLCR registers
  *slcr_lock = SLCR_LOCK_CODE;
}

int main(int argc, char *argv[])
{
  int fd; // File descriptor

  // Open the filesystem memory
  if((fd = open("/dev/mem", O_RDWR)) < 0) {
    perror("open");
    return EXIT_FAILURE;
  }
  // Map the SLCR base
  slcr = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, SLCR_BASE);
  close(fd); // Close the file descriptor for /dev/mem

  // Map the SLCR registers
  slcr_lock     = &slcr[SLCR_LOCK_REG_OFFSET];
  slcr_unlock   = &slcr[SLCR_UNLOCK_REG_OFFSET];
  fclk0_ctrl    = &slcr[FCLK0_CTRL_REG_OFFSET];

  printf("Registers mapped\n"); fflush(stdout);

  // Unlock the SLCR registers
  *slcr_unlock = SLCR_UNLOCK_CODE;
  // Read the current FCLK0 control register
  uint32_t fclk0_ctrl_val = *fclk0_ctrl;
  // Lock the SLCR registers
  *slcr_lock = SLCR_LOCK_CODE;
  // Extract the divisors
  uint32_t div0 = (fclk0_ctrl_val >>  8) & FCLK0_DIVISOR_MAX;
  uint32_t div1 = (fclk0_ctrl_val >> 20) & FCLK0_DIVISOR_MAX;

  printf("FCLK0 control register: div0 = %u, div1 = %u\n", div0, div1);
  
  while(1) {
    int divisor_num;
    uint32_t divisor_value;

    printf("Enter divisor number (0 for div0, 1 for div1) and divisor value: ");
    if (scanf("%d %u", &divisor_num, &divisor_value) != 2) {
      printf("Invalid input. Please enter a valid divisor number and value.\n");
      continue;
    }

    if (divisor_value > FCLK0_DIVISOR_MAX) {
      printf("Invalid divisor value. Maximum allowed value is %u.\n", FCLK0_DIVISOR_MAX);
      continue;
    }

    if (divisor_num == 0) {
      div0 = divisor_value;
    } else if (divisor_num == 1) {
      div1 = divisor_value;
    } else {
      printf("Invalid divisor number. Please enter 0 for div0 or 1 for div1.\n");
      continue;
    }

    set_fclk0(div0, div1);
    printf("FCLK0 control register updated: div0 = %u, div1 = %u\n", div0, div1);
  }
}
