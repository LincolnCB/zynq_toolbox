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
  
  *dac_enable = 0x0;
  exit(1); 
}

int main(int argc, char *argv[])
{

  //// Initialize variables and check arguments

  int fd;
  void *cfg;
  volatile uint32_t *slcr, \
    *dac_ctrl, *dac_enable, *dac_nsamples, *dac_board_offset, *dac_version, \
    *dac_control_register, *dac_trigger_count, *dac_refresh_divider, \
    *shim_memory, \
    *trigger_ctrl, *tc_trigger_count, *trigger_lockout_ptr, *trigger_polarity, *trigger_enable;
  
  if (argc != 5) {
    fprintf(stderr, "Usage: %s <trigger lockout (ms)> <fclk_divider_0> <fclk_divider_1> <inputfile>\n", argv[0]);
    exit(-1);
  }

  int fclk0_div0 = atoi(argv[2]);
  int fclk0_div1 = atoi(argv[3]);

  if (fclk0_div0 > 63 || fclk0_div1 > 63) {
    fprintf(stderr, "FCLK dividers must be less than 64\n");
    fprintf(stderr, "Usage: %s <trigger lockout (ms)> <fclk_divider_0> <fclk_divider_1> <inputfile>\n", argv[0]);
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
    // check if we have enough memory
    if(line_counter * 32 > 65536) {
      fprintf(stderr, "Not enough block RAM in this FPGA for your file with this software ! Try staying below %d samples.\n", 65536/32);
      exit(-1);
    }
    
    // allocate memory
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
    
    fprintf(stdout, "|"); fflush(stdout);
    rewind(input_file);
    unsigned int lrcounter = 0;
    do {
      line_length = 2048;
      ssize_t nchars = getline((char **) &linebuffer, &line_length, input_file);
      if(nchars <= 0)
        break;
      if(linebuffer[0] == '#')
        continue;

      int val, offset;
      char *linebuffer_p = linebuffer;
      // found a valid line
      for(int k=0; k<32; k++) {
        if(sscanf(linebuffer_p, " %d%n", &val, &offset) == 0) {
          fprintf(stderr, "some sort of parsing error !\n");
          fprintf(stderr, "original line: %s\n", linebuffer);
          fprintf(stderr, "line fragment %d parsed: %s\n", k, linebuffer_p);
          exit(-1);
        }
        linebuffer_p = linebuffer_p + offset;
        waveform_buffer[k][lrcounter] = val;
      }
      fprintf(stdout, "."); fflush(stdout);
      lrcounter++;
    } while(1);
    fprintf(stdout, "|"); fflush(stdout);
    
    fprintf(stdout, "\n");
    
    fclose(input_file);
  } else {
    fprintf(stderr, "Cannot open input file %s for reading !\n", filename);
    exit(-1);
  }

  sleep(1);



  //// Install SIGINT handler

  fprintf(stdout, "Installing SIGINT handler...\n"); fflush(stdout);
  struct sigaction sigIntHandler;
  sigIntHandler.sa_handler = sigint_handler;
  sigemptyset(&sigIntHandler.sa_mask);
  sigIntHandler.sa_flags = 0;
  
  sigaction(SIGINT, &sigIntHandler, NULL);

  sleep(1);


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

  sleep(1);

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

  sleep(1);
  
  printf("Trigger lockout = %d FPGA clockcycles\n", *trigger_lockout_ptr);
  *trigger_polarity = 1;
  *trigger_enable = 1;
  
  printf("FPGA version = %08lX\n", *dac_version);

  if(*dac_version != 0xffff0005) {
    printf("This tool only supports FPGA software version 5 or newer!!\n");
    exit(0);
  }

  *dac_nsamples = line_counter * 8;
  *dac_board_offset = line_counter * 8; // the boards copy each other
  int dbo = *dac_board_offset;

  fprintf(stdout, "board offset %d words\n", dbo);
  


  //// Load the sequence into the shim memory

  for (int sample=0; sample<line_counter; sample++)  {
    for (int channel=0; channel<8; channel++) {
      // board zero
      shim_memory[sample*8+channel      ] = ((channel | DAC_CMD) << 16) + (waveform_buffer[channel][sample] & 0xffff);
      // board one
      shim_memory[sample*8+channel+dbo  ] = ((channel | DAC_CMD) << 16) + (waveform_buffer[8+channel][sample] & 0xffff);
      // board two
      shim_memory[sample*8+channel+2*dbo] = ((channel | DAC_CMD) << 16) + (waveform_buffer[16+channel][sample] & 0xffff);
      // board three
      shim_memory[sample*8+channel+3*dbo] = ((channel | DAC_CMD) << 16) + (waveform_buffer[24+channel][sample] & 0xffff);
    }
  }
  
  // set the DAC to external SPI clock, not fully working, so set it to 0x0 (enable is 0x1)
  *dac_control_register = 0x0;

  // set to 50 KHz
  // LCB -- set to 1000 to match Don's divider
  *dac_refresh_divider = 1000;
  
  *dac_enable = 0x1;


  //// Main loop

  while(1) {
    printf(".... trigger count = %d (tc = %d)!\n", *dac_trigger_count, *tc_trigger_count); fflush(stdout);
    sleep(2);
  }
  
  sleep(5);
  *dac_enable = 0x0;
  return EXIT_SUCCESS;
} // End main
