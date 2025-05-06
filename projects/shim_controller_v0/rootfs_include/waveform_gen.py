import numpy as np
import matplotlib.pyplot as plt
import os
output_dir = 'out/shim_waveforms'
if not os.path.exists(output_dir):
  os.makedirs(output_dir)

def save_array_to_file(array, filename):
  if not issubclass(array.dtype.type, np.integer):
    raise ValueError("Array must be of integer type")
  with open(filename, 'w') as f:
    for line in array:
      f.write(' '.join(map(str, line)) + '\n')

# Example usage

def eight_channel_offset(offset_amps, runtime_ms):
  samples = runtime_ms * 50
  array = np.zeros((samples, 32)) + 1.0
  array[:, :8] = array[:, :8] + (offset_amps / 4.0)
  array[-2:, :] = 1.0
  array = array * 2**15
  array = np.round(array).astype(np.int32)
  return array

def one_channel_sine(channel, freq_hz, amplitude_amps, runtime_ms):
  samples = runtime_ms * 50
  array = np.zeros((samples, 32)) + 1.0
  time_ms = np.linspace(0, runtime_ms, samples)
  array[:, channel] = array[:, channel] + (amplitude_amps / 4.0) * np.sin(2 * np.pi * freq_hz * time_ms / 1000)
  array[-2:, :] = 1.0
  array = array * 2**15
  array = np.round(array).astype(np.int32)
  return array

def all_channel_sine(freq_hz, amplitude_amps, runtime_ms):
  samples = runtime_ms * 50
  array = np.zeros((samples, 32)) + 1.0
  time_ms = np.linspace(0, runtime_ms, samples).reshape(-1, 1)
  array[:, :8] = array[:, :8] + (amplitude_amps / 4.0) * np.sin(2 * np.pi * freq_hz * time_ms / 1000)
  array[-2:, :] = 1.0
  array = array * 2**15
  array = np.round(array).astype(np.int32)
  return array

def channel_identifier(width=100, height=0.05, channels=32):
  bits = int(np.ceil(np.log2(channels)))
  array = np.zeros((width * (bits + 2), channels))
  array[:width, :] = np.kaiser(width, 9).reshape(-1,1) * height/2.0
  array[-width:, :] = np.kaiser(width, 9).reshape(-1,1) * height/2.0
  for channel in range(channels):
    for bit in range(bits):
      if (channel >> bit) & 1:
        array[width * (bit + 1):width * (bit + 2), channel] = np.kaiser(width, 9) * height
      else:
        array[width * (bit + 1):width * (bit + 2), channel] = np.kaiser(width, 9) * -height
  array = (array + 1.0) * 2**15
  array = np.round(array).astype(np.int32)
  return array


array = channel_identifier()
save_array_to_file(array, f'{output_dir}/binary_50mA_channel_id.txt')

freq_khz = 20
amps_ma = 2000
array = one_channel_sine(5, freq_khz * 1000, amps_ma / 1000, 5)
save_array_to_file(array, f'{output_dir}/ch5_sine/{freq_khz}kHz_{amps_ma}mA_5ms.txt')
array = all_channel_sine(freq_khz * 1000, amps_ma / 1000, 5)
save_array_to_file(array, f'{output_dir}/all-ch_sine/{freq_khz}kHz_{amps_ma}mA_5ms.txt')

# array = eight_channel_offset(0, 13)
# save_array_to_file(array, f'{output_dir}/all-ch_offset_0mA_13ms.txt')

# array = eight_channel_offset(0.1, 13)
# save_array_to_file(array, f'{output_dir}/all-ch_offset_100mA_13ms.txt')

# for channel in range(8):
#   array = one_channel_sine(channel, 250, 1.0, 10)
#   save_array_to_file(array, f'{output_dir}/ch{channel}_sine_250Hz_1A_10ms.txt')

# array = all_channel_sine(250, 0.5, 13)
# save_array_to_file(array, f'{output_dir}/all-ch_sine_250Hz_500mA_13ms.txt')


