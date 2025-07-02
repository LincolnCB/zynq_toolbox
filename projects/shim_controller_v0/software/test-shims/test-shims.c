#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <math.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>

// Bitmask lock/unlock codes
#define SLCR_LOCK_CODE 0x767B
#define SLCR_UNLOCK_CODE 0xDF0D
#define FCLK0_UNRESERVED_MASK 0x03F03F30

#define FCLK0_BASELINE_FREQ 2e9

// 4-bit command word used by DAC to write to channel register, but not update the output:
// 0b0000 for LTC2656, 0b0001 for AD5676
#define DAC_CMD 0b00010000

// Zero out the shim memory
void clear_shim_waveforms( volatile uint32_t *shim)
{
  for (int k=0; k<65536; k++) {
    shim[k] = 0x0;
  }        
}
 
// Handle SIGINT
void sigint_handler(int s){
  fprintf(stderr, "Caught SIGINT signal %d! Shutting down waveform trigger\n", s);
  int fd;
  if((fd = open("/dev/mem", O_RDWR)) < 0) {
    perror("open");
    exit(1);
  }
  volatile uint32_t *dac_ctrl = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40201000);
  volatile uint32_t *dac_enable = ((uint32_t *)(dac_ctrl+3));

  volatile uint32_t *cfg = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40200000);
  volatile uint32_t *n_shutdown_force = ((uint32_t *)(cfg));
  
  fprintf(stderr, "Setting shutdown force...\n");
  *n_shutdown_force = 0x0;
  fprintf(stderr, "Disabling DAC...\n");
  *dac_enable = 0x0;
  exit(1);
}

int main(int argc, char *argv[])
{

  //// Initialize variables and check arguments

  int fd;
  void *cfg;
  volatile uint32_t *slcr, \
    *n_shutdown_force, *shutdown_reset, \
    *dac_ctrl, *dac_enable, *dac_nsamples, *dac_board_offset, *dac_version, \
    *dac_control_register, *dac_trigger_count, *dac_refresh_divider, \
    *shim_memory, \
    *trigger_ctrl, *tc_trigger_count, *trigger_lockout_ptr, *trigger_polarity, *trigger_enable;
  
  if (!(argc == 6) && !(argc == 7)) {
    fprintf(stderr, "Usage: %s <trigger lockout (ms)> <fclk_divider_0> <fclk_divider_1> <inputfile> <dac_refresh_divider> [board_to_log]\n", argv[0]);
    exit(-1);
  }

  int fclk0_div0 = atoi(argv[2]);
  int fclk0_div1 = atoi(argv[3]);

  if (fclk0_div0 > 63 || fclk0_div1 > 63) {
    fprintf(stderr, "FCLK dividers must be less than 64\n");
    fprintf(stderr, "Usage: %s <trigger lockout (ms)> <fclk_divider_0> <fclk_divider_1> <inputfile> [board_to_log]\n", argv[0]);
    exit(-1);
  }
  int board_to_log = 0;
  if (argc == 7) {
    board_to_log = atoi(argv[6]);
    if (board_to_log < 0 || board_to_log > 3) {
      fprintf(stderr, "Board to log must be 0, 1, 2, or 3\n");
      fprintf(stderr, "Usage: %s <trigger lockout (ms)> <fclk_divider_0> <fclk_divider_1> <inputfile> <dac_refresh_divider> [board_to_log]\n", argv[0]);
      exit(-1);
    }
  }

  int user_dac_divider = atoi(argv[5]);
  if (user_dac_divider < 300) {
    fprintf(stderr, "DAC refresh divider must be a positive integer of at least 300\n");
    fprintf(stderr, "Usage: %s <trigger lockout (ms)> <fclk_divider_0> <fclk_divider_1> <inputfile> <dac_refresh_divider> [board_to_log]\n", argv[0]);
    exit(-1);
  }

  //// Read the input file

  char *filename = argv[4];
  char *linebuffer;
  unsigned int line_length;
  unsigned int line_counter = 0;
  int **waveform_buffer = NULL;

  linebuffer = (char *) malloc(2048);
  
  FILE *input_file = fopen(filename, "r");
  if(input_file != NULL) {
    do {
      line_length = 2048;
      ssize_t nchars = getline((char **) &linebuffer, &line_length, input_file);
      if(nchars <= 0)
        break;
      if(linebuffer[0] != '#')
        line_counter++;
    } while(1);
    
    fprintf(stdout, "%d waveform samples found !\n", line_counter);
    // Check if we have enough memory
    if(line_counter * 32 > 65536) {
      fprintf(stderr, "Not enough block RAM in this FPGA for your file with this software ! Try staying below %d samples.\n", 65536/32);
      exit(-1);
    }
    
    // Allocate memory -- 32 channels
    waveform_buffer = (int **) malloc(32*sizeof(int *));
    if(waveform_buffer == NULL) {
      fprintf(stderr, "Error allocating waveform memory !\n");
      exit(-1);
    }
    
    for (int k=0; k<32; k++) {
      waveform_buffer[k] = (int *) malloc(line_counter*sizeof(int));
      if(waveform_buffer[k] == NULL) {
        fprintf(stderr, "Error allocating waveform memory !\n");
        exit(-1);
      }
    }
    
    fprintf(stdout, ":"); fflush(stdout);
    rewind(input_file);
    unsigned int line_read_counter = 0;
    do {
      line_length = 2048;
      ssize_t nchars = getline((char **) &linebuffer, &line_length, input_file);
      if(nchars <= 0)
        break;
      if(linebuffer[0] == '#')
        continue;

      int val, offset;
      char *linebuffer_p = linebuffer;

      // Read valid lines
      for(int k=0; k<32; k++) {
        if(sscanf(linebuffer_p, " %d%n", &val, &offset) == 0) {
          fprintf(stderr, "some sort of parsing error !\n");
          fprintf(stderr, "original line: %s\n", linebuffer);
          fprintf(stderr, "line fragment %d parsed: %s\n", k, linebuffer_p);
          exit(-1);
        }
        linebuffer_p = linebuffer_p + offset;
        waveform_buffer[k][line_read_counter] = val;
      }
      fprintf(stdout, "."); fflush(stdout);
      line_read_counter++;
    } while(1);
    fprintf(stdout, ":"); fflush(stdout);
    
    fprintf(stdout, "\n");
    
    fclose(input_file);
  } else {
    fprintf(stderr, "Cannot open input file %s for reading !\n", filename);
    exit(-1);
  }

  usleep(250000);



  //// Install SIGINT handler

  fprintf(stdout, "Installing SIGINT handler...\n"); fflush(stdout);
  struct sigaction sigIntHandler;
  sigIntHandler.sa_handler = sigint_handler;
  sigemptyset(&sigIntHandler.sa_mask);
  sigIntHandler.sa_flags = 0;
  
  sigaction(SIGINT, &sigIntHandler, NULL);

  usleep(250000);


  //// Map the memory
  
  fprintf(stdout, "Opening /dev/mem...\n"); fflush(stdout);
  if((fd = open("/dev/mem", O_RDWR)) < 0) {
    perror("open");
    return EXIT_FAILURE;
  }

  // set up shared memory (please refer to the memory offset table)
  fprintf(stdout, "Mapping FPGA memory...\n"); fflush(stdout);
  slcr = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0xF8000000);
  cfg = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40200000);
  dac_ctrl = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40201000);
  trigger_ctrl = mmap(NULL, sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40202000);
  /*
    NOTE: The block RAM can only be addressed with 32 bit transactions, so gradient_memory needs to
    be of type uint32_t. The HDL would have to be changed to an 8-bit interface to support per
    byte transactions
  */
  
  // shim_memory is now a full 256k
  printf("Mapping shim memory...\n"); fflush(stdout);

  shim_memory = mmap(NULL, 64*sysconf(_SC_PAGESIZE), PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0x40000000);
  
  printf("Clearing shim memory...\n"); fflush(stdout);

  clear_shim_waveforms(shim_memory);
    
  printf("Setting FPGA clock divisors...\n"); fflush(stdout);
  printf("Div0 = %d, Div1 = %d\n", fclk0_div0, fclk0_div1);
  printf("Base frequency = %f MHz\n", FCLK0_BASELINE_FREQ / 1e6);
  printf("Target frequency = %f MHz\n", FCLK0_BASELINE_FREQ / (fclk0_div0 * fclk0_div1) / 1e6);
  /* set FPGA clock to 50 MHz */
  slcr[2] = SLCR_UNLOCK_CODE;
  slcr[92] = (slcr[92] & ~FCLK0_UNRESERVED_MASK) \
    | (fclk0_div1 << 20) \
    | (fclk0_div0 <<  8);
  slcr[2] = SLCR_LOCK_CODE;
  printf(".... Done !\n"); fflush(stdout);

  usleep(250000);

  // Map the shutdown reset
  n_shutdown_force = ((uint32_t *)(cfg));
  shutdown_reset = ((uint32_t *)(cfg)+1);

  // Check version etc
  dac_nsamples = ((uint32_t *)(dac_ctrl+0));
  dac_board_offset = ((uint32_t *)(dac_ctrl+1));
  dac_control_register  = ((uint32_t *)(dac_ctrl+2));
  dac_enable = ((uint32_t *)(dac_ctrl+3));
  dac_refresh_divider = ((uint32_t *)(dac_ctrl+4));
  
  dac_version = ((uint32_t *)(dac_ctrl+10));
  dac_trigger_count = ((uint32_t *)(dac_ctrl+9));
  tc_trigger_count = ((uint32_t *)(trigger_ctrl+4));
  trigger_lockout_ptr = ((uint32_t *)(trigger_ctrl + 1));
  trigger_polarity = ((uint32_t *)(trigger_ctrl+2));
  trigger_enable = ((uint32_t *)(trigger_ctrl));

  *trigger_lockout_ptr = (uint32_t)(floor(atof(argv[1]) * 1e-3 * FCLK0_BASELINE_FREQ / (fclk0_div0 * fclk0_div1)));

  usleep(250000);
  
  printf("Trigger lockout = %d FPGA clockcycles\n", *trigger_lockout_ptr);
  *trigger_polarity = 1;
  *trigger_enable = 1;
  
  printf("FPGA version = %08lX\n", *dac_version);

  if(*dac_version != 0xffff0005) {
    printf("This tool only supports FPGA software version 5 or newer!!\n");
    exit(0);
  }

  *dac_nsamples = line_counter * 8;
  *dac_board_offset = line_counter * 8; // the boards have the same amount of samples
  int dbo = *dac_board_offset;

  fprintf(stdout, "board offset %d words\n", dbo);

  // Release the shutdown force
  printf("Releasing shutdown force...\n"); fflush(stdout);
  *n_shutdown_force = 0x1;
  // Sleep 100ms to let the DAC come out of shutdown
  usleep(100000);
  // Pulse the shutdown reset for 100us
  printf("Pulsing shutdown reset...\n"); fflush(stdout);
  *shutdown_reset = 0x1;
  usleep(100);
  *shutdown_reset = 0x0;
  // Sleep 100ms to let everything boot up
  usleep(100000);


  //// Load the sequence into the shim memory

  for (int sample = 0; sample < line_counter; sample++)  {
    for (int channel = 0; channel < 8; channel++) {
      for (int board = 0; board < 4; board++) {
        shim_memory[board * dbo + sample * 8 + channel] = \
          ((channel | DAC_CMD) << 16) + (waveform_buffer[board * 8 + channel][sample] & 0xffff);
      }
    }
  }

  //// Check the sequence in the shim memory
  if (argc == 6) {
    int cmd_word = 0x0;
    printf("Logging board %d\n", board_to_log);
    fd = open("shim.log", O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd < 0) {
      perror("open");
      exit(1);
    }
    for (int sample = 0; sample < line_counter; sample++) {
      dprintf(fd, "Sample %d\n", sample);
      for (int channel = 0; channel < 8; channel++) {

        // Print the expected values
        dprintf(fd, "Expected:\n");
        dprintf(fd, "  Ch%02d to %05d [0b", channel, waveform_buffer[board_to_log*8+channel][sample]);
        cmd_word = ((channel | DAC_CMD) << 16) + (waveform_buffer[board_to_log*8+channel][sample] & 0xffff);
        for (int bit = 23; bit >= 0; bit--) {
          dprintf(fd, "%d", (cmd_word >> bit) & 0x1);
        }
        dprintf(fd, "]\n");

        // // DOESN'T WORK BECAUSE SHIM_MEMORY IS WRITE ONLY
        // // Print the loaded values
        // cmd_word = shim_memory[sample*8+channel+board_to_log*dbo];
        // dprintf(fd, "Loaded:\n");
        // dprintf(fd, "  Ch%02d to %05d [0b", (cmd_word >> 16) & 0xf, cmd_word & 0xffff);
        // for (int bit = 23; bit >= 0; bit--) {
        //   dprintf(fd, "%d", (cmd_word >> bit) & 0x1);
        // }
        // dprintf(fd, "]\n");
      }
    }
  }
  
  // set the DAC to external SPI clock, not fully working, so set it to 0x0 (enable is 0x1)
  *dac_control_register = 0x0;

  // Clock cycles per DAC sample
  *dac_refresh_divider = user_dac_divider;
  printf("DAC refresh divider = %d\n", user_dac_divider); fflush(stdout);

  // enable the DAC
  printf("Enabling DAC...\n"); fflush(stdout);
  *dac_enable = 0x1;


  //// Main loop

  while(1) {
    printf(".... trigger count = %d (tc = %d)!\n", *dac_trigger_count, *tc_trigger_count); fflush(stdout);
    sleep(3);
  }
  
  sleep(1);
  *n_shutdown_force = 0x0;
  *dac_enable = 0x0;
  return EXIT_SUCCESS;
} // End main
