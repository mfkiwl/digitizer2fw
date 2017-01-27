# Digitizer2 Python User Guide
The prerequisites for this guide are the [fpga-device-server](https://github.com/pwuertz/fpga-device-server), its python reference client and a digitizer2 FPGA bitfile. For precompiled FPGA bitfiles check the [firmware releases](https://github.com/pwuertz/digitizer2fw/releases).

## Device server
The fpga firmware is designed to communicate with the [*fpga-device-server* application. The server takes care of device discovery, firmware upload and data transfers. At startup it requires a `config.json` configuration file which is loaded from the current working directory. The configuration defines which devices are to be claimed by the server, the location of firmware bitfiles and an optional list of register addresses for periodic polling.

The following configuration can be used for claiming and initializing digitizer2 devices and monitoring their global status register for changes:

```config.json```
```json
{
    "DeviceDescriptions": [
        {
            "name": "Digitizer2",
            "prefix": "DIGI2",
            "bitfile": "digitizer2-firmware.bit",
            "watchlist": [ [0,1] ]
        }
    ],
    "Server": {
        "port": 9002
    }
}
```

Make sure that the *fpga-device-server* application has permissions to access the USB devices, ideally managed by *udev* rules. On successful startup the server identifies the connected USB devices and initializes the hardware. Example output:
```no-highlight
$ ./fpga-device-server
Starting device-server
Listening on: 0.0.0.0:9002
New device: Digitizer2, TU KL, DIGI29LUBF
Adding DIGI29LUBF: Digitizer2
Programming DIGI29LUBF: digitizer2-firmware.bit
Finished programming DIGI29LUBF
```

## Test application
For interacting with the device server, a reference python client ```QTestApplication.py``` is included in the *fpga-device-server* repository. If the server is running locally using the default port this application can be launched directly. After establishing the connection to the server it will display all claimed devices and allow reading/writing their firmware registers.

However, for the digitizer2 firmware it is more convenient to add some higher level functionality instead of accessing the registers directly. This is accomplished by importing and adding the mixin class from `scripts/Digitizer2Mixin.py`. The following script takes care of including the high level methods for digitizer2 and launching the test application. It requires the `pyfpgaclient` library from *fpga-device-server*, which must be in the python search path. Either install this module or add its folder to `sys.path`.

`digitizer2-test-application.py`
```
### digitizer2 test application
# import sys; sys.path.append("/path/to/pyfpgaclient/library")
from pyfpgaclient import QTestApplication
from Digitizer2Mixin import Digitizer2Mixin
QTestApplication.QFpgaClient.registerDeviceMixin("DIGI2", Digitizer2Mixin)
QTestApplication.run(port=9002)
```

When launching the application, all devices known to the server are listed and the basic device functions are accessible as buttons for convenience. The embedded python console included in the application allows full access to the *pyfpgaclient* device API.

## Usage

### Power up
For starting up the digitizer first enable the analog power and initialize the ADC. The ADC must be initialized even when an application only requires digital sampling since the sampling clock is derived from the ADC.
```
# power up ADC
dev.adc_power(True)
dev.adc_device_enable(True)
```
The device will now start consuming more power and build up heat. The temperature can be monitored internally with `dev.adc_temperature()` and should not exceed 85 °C.



For shutting down the device it is advised to use the reverse order.
```
# power down ADC
dev.adc_device_enable(False)
dev.adc_power(False)
```

### Acquisition
An acquisition is started by resetting the acquisition logic. Once ready, the device will wait for a start trigger event before recording data. The acquisition is running until a stop trigger occurs or the internal buffer is full.

The current acquisition state can be monitored by checking `dev.get_status()` or handling status change events from the device server.

- s_reset - Reset active
- s_wait_ready - Wait until reset is completed
- s_waittrig - Wait for start trigger
- s_buffering - Acquisition running
- s_done - Acquisition stopped

The number of stored data words from the current acquisition can be retrived by `dev.acq_buffer_count()`. When the acquisition is finished the data is read using `dev.acq_buffer_read()`.

A typical sequence might look like this:
```
dev.acq_reset(True)
# optional: wait for transition to state s_reset
dev.acq_reset(False)
# wait for state s_done or call dev.acq_stop()
data = dev.acq_buffer_read()
```

In its default configuration the device will start the acquisition immediately using an internal trigger source and return the raw samples from the analog and digital channels.

### Configuration
For using the TDC functionality of the firmware or for adapting to more specific use cases the device must be configured before starting the acquisition.

The analog input logic includes a moving average filter for noise reduction and inverting the polarity of the incoming signal. Also it is advised to set a reasonable threshold above the noise level for the peak detection logic.
```
# invert and smooth analog signal
dev.analog_invert(True)
dev.analog_average(2)
# set peak detection threshold (ADC units)
dev.maxfind_threshold(50)
```

Trigger sources for starting and stopping an acquisition allow for internal and external control of the acquisition process.
```python
# start acquisition on rising edge at D1, stop on falling edge
dev.acq_start_trig_src(dev.TriggerSource.D1_RISING)
dev.acq_stop_trig_src(dev.TriggerSource.D1_FALLING)
```

The acquisition mode defines which data is written to the acquisition buffer and allows for different kinds of measurements.
```
# setup acquisition in TDC mode
dev.acq_mode(dev.AcqMode.TDC)
```
Available modes are:

- RAW acquisition (default). Store all analog and digital samples. Primarily used to inspect the incoming analog signal.
- TDC acquisition. Only store the timing information of digital rising edges and analog peak maxima.
- MAXFIND acquisition. Only store timing and height of analog peak maxima.

When reading the buffer using `dev.acq_buffer_read()` the data is automatically parsed depending on the current acquisition mode. Alternatively, `dev.acq_buffer_read_raw()` can be used to read out the raw data, continuously if required, for subsequent parsing and processing. 
