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
#define FCLK0_143MHZ_MASK  0x00100700
#define FCLK0_10MHZ_MASK   0x00A01400
#define FCLK0_5MHZ_MASK    0x01401400
#define FCLK0_2500KHZ_MASK 0x01402800

int main(int argc, char *argv[])
{
  int fd; // File descriptor

  // System Level Control Registers -- each is 32 bits, so the pointer is uint32_t
  volatile uint32_t *slcr; // Base pointer
  volatile uint32_t *slcr_lock, *slcr_unlock, *fclk0_ctrl;

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

  printf("Setup standard memory maps !\n"); fflush(stdout);

  while(1) {
    // Unlock the SLCR registers
    *slcr_unlock = SLCR_UNLOCK_CODE;
    // Set the FCLK0 to 10 MHz
    *fclk0_ctrl = *fclk0_ctrl & ~FCLK0_UNRESERVED_MASK | FCLK0_10MHZ_MASK;
    // Lock the SLCR registers
    *slcr_lock = SLCR_LOCK_CODE;
    printf("10 MHz!\n"); fflush(stdout);
    sleep(2);

    // Unlock the SLCR registers
    *slcr_unlock = SLCR_UNLOCK_CODE;
    // Set the FCLK0 to 5 MHz
    *fclk0_ctrl = *fclk0_ctrl & ~FCLK0_UNRESERVED_MASK | FCLK0_5MHZ_MASK;
    // Lock the SLCR registers
    *slcr_lock = SLCR_LOCK_CODE;
    printf("5 MHz!\n"); fflush(stdout);
    sleep(2);

    // Unlock the SLCR registers
    *slcr_unlock = SLCR_UNLOCK_CODE;
    // Set the FCLK0 to 2.5 MHz
    *fclk0_ctrl = *fclk0_ctrl & ~FCLK0_UNRESERVED_MASK | FCLK0_2500KHZ_MASK;
    // Lock the SLCR registers
    *slcr_lock = SLCR_LOCK_CODE;
    printf("2.5 MHz!\n"); fflush(stdout);
    sleep(2);
  }
}
