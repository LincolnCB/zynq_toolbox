import numpy as np

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
  array[-1, :] = 1.0
  array = array * 2**15
  array = np.round(array).astype(np.int32)
  return array

def one_channel_sine(channel, freq_hz, amplitude_amps, runtime_ms):
  samples = runtime_ms * 50
  array = np.zeros((samples, 32)) + 1.0
  time_ms = np.linspace(0, runtime_ms, samples)
  array[:, channel] = array[:, channel] + (amplitude_amps / 4.0) * np.sin(2 * np.pi * freq_hz * time_ms / 1000)
  array[-1, :] = 1.0
  array = array * 2**15
  array = np.round(array).astype(np.int32)
  return array

def all_channel_sine(freq_hz, amplitude_amps, runtime_ms):
  samples = runtime_ms * 50
  array = np.zeros((samples, 32)) + 1.0
  time_ms = np.linspace(0, runtime_ms, samples).reshape(-1, 1)
  array[:, :8] = array[:, :8] + (amplitude_amps / 4.0) * np.sin(2 * np.pi * freq_hz * time_ms / 1000)
  array[-1, :] = 1.0
  array = array * 2**15
  array = np.round(array).astype(np.int32)
  return array


array = eight_channel_offset(0, 13)
save_array_to_file(array, f'tmp/all-ch_offset_0mA_13ms.txt')

# channel = 0
# array = one_channel_sine(channel, 250, 1.0, 10)
# save_array_to_file(array, f'tmp/ch{channel}_sine_250Hz_1A_10ms.txt')

# array = all_channel_sine(250, 0.5, 13)
# save_array_to_file(array, f'tmp/all-ch_sine_250Hz_500mA_13ms.txt')
