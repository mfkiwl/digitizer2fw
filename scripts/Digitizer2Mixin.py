import numpy as np
import time
REG_CONFIG = (0, 0)
REG_STATUS = (0, 1)
REG_VERSION = (0, 3)
REG_A_THRESHOLD = (0, 4)
PORT_RAM = 2
PORT_ADCPROG = 3
PORT_ACQBUF = 4


class Digitizer2Mixin(object):

    def get_version(self):
        return self.read_reg(*REG_VERSION)

    def get_status(self):
        return self.__status_to_dict(self.read_reg(*REG_STATUS))

    @staticmethod
    def __status_to_dict(status_val):
        return {
            "init_calib_complete": bool(status_val & (1 << 0)),
            "ram_app_rdy": bool(status_val & (1 << 1)),
            "ram_app_wdf_rdy": bool(status_val & (1 << 2)),
        }

    ###################################################

    def get_config_bit(self, bit):
        conf_val = self.read_reg(*REG_CONFIG)
        return bool(conf_val & (1 << bit))

    def set_config_bit(self, bit, enabled):
        conf_val = self.read_reg(*REG_CONFIG)
        if enabled:
            conf_val |= (1 << bit)
        else:
            conf_val &= ~(1 << bit)
        self.write_reg(REG_CONFIG[0], REG_CONFIG[1], conf_val)

    ###################################################

    def adc_power(self, enabled):
        self.set_config_bit(1, enabled)

    ###################################################

    def adc_program(self, addr, value):
        self.write_reg(PORT_ADCPROG, 0, addr)
        self.write_reg(PORT_ADCPROG, 1, value)

    def adc_program_read(self, addr):
        wr_addr = addr | (1 << 7)
        self.write_reg(PORT_ADCPROG, 0, wr_addr)
        time.sleep(0.01)
        return self.read_reg(PORT_ADCPROG, 0)

    def adc_program_test(self, pattern="toggle2"):
        patterns = {
            False: (0, 0, 0),
            "0": (0x8000, 0x0000, 0x0000),
            "1": (0xbffc, 0x3ffc, 0x3ffc),
            "toggle1": (0x9554, 0x2aa8, 0x1554),
            "toggle2": (0xbffc, 0x0000, 0x3ffc),
        }
        pattern_words = patterns[pattern]
        for i in range(3):
            print("adcprog %x %x" % (0x3c + i, pattern_words[i]))
            self.adc_program(0x3c + i, pattern_words[i])

    ###################################################

    def _adc_device_enable(self, enabled):
        self.set_config_bit(3, enabled)

    def _adc_device_reset(self, enabled):
        self.set_config_bit(2, enabled)

    def _adc_program_autocorr_strobe(self):
        self.adc_program(0x03, 0b0100101100011000)
        self.adc_program(0x03, 0b0000101100011000)

    def adc_program_highperf(self, enabled):
        value = 0b1000000000000010 if enabled else 0b1000000000000000
        self.adc_program(0x1, value)

    def adc_temperature(self):
        return self.adc_program_read(0x2b)

    def _adc_device_init_regs(self):
        self.adc_program(0x00, 0b0000000000000000)  # no decimation, no filter
        self.adc_program(0x01, 0b1000000000000010)  # corr en, fmt int12, hp mode1
        self.adc_program(0x0e, 0b0000000000000000)  # no sync
        self.adc_program(0x0f, 0b0000000000000000)  # no sync, 1.0V vref
        self.adc_program(0x38, 0b1111111111011111)  # hp mode2, bias en, no sync, lp mode
        self.adc_program(0x3a, 0b1101100000011011)  # 3.5mA LVDS current
        self.adc_program(0x66, 0b0000111111111111)  # LVDS output bus power (disable unused)

    def adc_device_enable(self, enabled):
        # disable device
        self._adc_device_enable(False)
        self._adc_device_reset(False)
        if enabled:
            time.sleep(0.01)
            # enable device
            self._adc_device_enable(True)
            time.sleep(0.01)
            # reset registers
            self._adc_device_reset(True)
            self._adc_device_reset(False)
            time.sleep(0.01)
            # setup registers
            self._adc_device_init_regs()
            self._adc_program_autocorr_strobe()
            self.sampling_reset()

    def _sampling_rst(self, enabled):
        self.set_config_bit(4, enabled)

    def sampling_reset(self):
        self._sampling_rst(True)
        time.sleep(0.01)
        self._sampling_rst(False)

    def _acq_reset(self, enabled):
        self.set_config_bit(5, enabled)

    def acq_data_select(self, source):
        self.set_config_bit(6, source & 0b01)
        self.set_config_bit(7, source & 0b10)

    def acq_trigger_mask(self, no_cnt=False, no_d1=True, no_d2=True, no_a=True):
        self.set_config_bit(11, no_cnt)
        self.set_config_bit(10, no_d1)
        self.set_config_bit(9, no_d2)
        self.set_config_bit(8, no_a)

    def acq_reset(self):
        self._acq_reset(True)
        self._acq_reset(False)

    def acq_buffer_count(self):
        return self.read_reg(PORT_ACQBUF, 0)

    def adc_buffer_read(self):
        # read buffer
        n = self.acq_buffer_count()
        data = self.read_reg_n(PORT_ACQBUF, 1, n)
        np.save("data.npy", data)
        return data

    def tdc_a_threshold(self, value):
        value_u16 = int(np.int16(value).view(np.uint16))
        self.write_reg(REG_A_THRESHOLD[0], REG_A_THRESHOLD[1], value_u16)

    ###################################################
    """
    def init_ram_buf(self):
        for i in range(8):
            self.write_ram_buf(i, i+1)

    def write_ram_buf(self, i, word):
        assert i < 8
        self.write_reg(PORT_RAM, i, word)

    def read_ram_buf(self):
        return [self.read_reg(PORT_RAM, i) for i in range(8)]

    def ram_write(self):
        self.write_reg(PORT_RAM, 8, 0)

    def ram_read(self):
        self.write_reg(PORT_RAM, 8, 1)
    """
