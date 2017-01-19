# -*- coding: utf-8 -*-
#-----------------------------------------------------------------------------
# fpga-device-server client library for digitizer2
#
# Author: Peter Würtz, TU Kaiserslautern (2016)
# Distributed under the terms of the GNU General Public License Version 3.
# The full license is in the file COPYING.txt, distributed with this software.
#-----------------------------------------------------------------------------


"""
Digitizer2 Python API
---------------------

The python API for the digitizer2 firmware is provided as a mixin class for
the pyfpgaclient reference library, included in fpga-device-server.
"""

from enum import IntEnum
import numpy as np
import time

REG_CONFIG = (0, 0)
REG_CONFIG_ACQ = (0, 5)
REG_STATUS = (0, 1)
REG_A_THRESHOLD = (0, 4)
PORT_RAM = 2
PORT_ADCPROG = 3
PORT_ACQBUF = 4


def parse_mode0(data_u16):
    """
    Parse data from RAW acquisition (mode=0).

    Returns timestamps for detected maxima on the analog channel and rising edges on the digital channels.

    :param data_u16: data from device
    :return: times_a_maxfound, times_d1_rising, times_d2_rising
    """

    # TODO: should use (numba) parser instead of creating intermediate arrays
    data_u16 = data_u16[:data_u16.size - (data_u16.size % 4)]  # clamp to multiple of 4
    n_samples_a = data_u16.size
    n_samples_d = 2 * n_samples_a

    DT_A = 2e-9
    DT_D = 1e-9
    T_a = np.arange(n_samples_a) * DT_A
    T_d1 = np.arange(n_samples_d) * DT_D
    T_d2 = np.arange(n_samples_d) * DT_D

    # analog samples (12bit signed)
    data_a = (np.bitwise_and(0x0fff, data_u16) << 4).view(np.int16) >> 4

    # digital samples
    def extract_d_samples(data_u16, channel_idx):
        assert (channel_idx is 0) or (channel_idx is 1)
        # get array of 4bit digital data, combine to 8bit, unpack to bool array
        bits_u4 = np.bitwise_and(0xf, data_u16[channel_idx::2] >> 12).astype(np.uint8)
        bits_u8 = (bits_u4[0::2] << 4) | bits_u4[1::2]
        data_bool = np.unpackbits(bits_u8)
        return data_bool

    data_d1 = extract_d_samples(data_u16, 0)
    data_d2 = extract_d_samples(data_u16, 1)

    return (T_a, data_a), (T_d1, data_d1), (T_d2, data_d2)


def parse_mode2(data_u16):
    """
    Parse data from TDC acquisition (mode=2).

    Returns timestamps for detected maxima on the analog channel and rising edges on the digital channels.

    :param data_u16: data from device
    :return: times_a_maxfound, times_d1_rising, times_d2_rising
    """
    data_u16 = data_u16[:data_u16.size - (data_u16.size % 2)]  # clamp to multiple of 2
    packets = (data_u16[0::2].astype(np.uint32) << 16) | (data_u16[1::2].astype(np.uint32))
    TDC_CNT_BITS = 22

    # get data from tdc packets
    # TODO: should use (numba) parser instead of creating intermediate arrays
    cnt_overflow = np.bitwise_and(1 << 31, packets).astype(bool)
    event_a = np.bitwise_and(1 << 30, packets).astype(bool)
    event_a_pos = ((packets >> 28) & 0b11).astype(np.uint8)
    event_d1 = np.bitwise_and(1 << 27, packets).astype(bool)
    event_d1_pos = ((packets >> 25) & 0b11).astype(np.uint8)
    event_d2 = np.bitwise_and(1 << 24, packets).astype(bool)
    event_d2_pos = ((packets >> 22) & 0b11).astype(np.uint8)
    cnt_values = np.bitwise_and(2**TDC_CNT_BITS - 1, packets)

    # track counter overflows and construct timestamp array
    times_out_a = np.zeros(np.count_nonzero(event_a), dtype=np.double)
    times_out_d1 = np.zeros(np.count_nonzero(event_d1), dtype=np.double)
    times_out_d2 = np.zeros(np.count_nonzero(event_d2), dtype=np.double)
    idx_a = 0
    idx_d1 = 0
    idx_d2 = 0
    DT_cyc = 4e-9
    DT = 1e-9
    cnt_accum = 0
    for i in range(packets.size):
        cnt_accum += 2**TDC_CNT_BITS * cnt_overflow[i]  # add counter length on overflow
        cnt_value = cnt_values[i]

        if event_a[i]:
            times_out_a[idx_a] = (cnt_accum + cnt_value) * DT_cyc + event_a_pos[i] * DT
            idx_a += 1

        if event_d1[i]:
            times_out_d1[idx_d1] = (cnt_accum + cnt_value) * DT_cyc + event_d1_pos[i] * DT
            idx_d1 += 1

        if event_d2[i]:
            times_out_d2[idx_d2] = (cnt_accum + cnt_value) * DT_cyc + event_d2_pos[i] * DT
            idx_d2 += 1

    return times_out_a, times_out_d1, times_out_d2


def parse_mode3(data_u16):
    """
    Parse data from analog maxfinder acquisition (mode=3).

    Returns timestamps peak heights for detected maxima on the analog channel.

    :param data_u16: data from device
    :return: times_a_maxfound, maxvalues
    """

    # TODO: should use (numba) parser instead of creating intermediate arrays

    data_u16 = data_u16[:data_u16.size - (data_u16.size % 2)]  # clamp to multiple of 2
    packets = (data_u16[0::2].astype(np.uint32) << 16) | (data_u16[1::2].astype(np.uint32))
    TDC_CNT_BITS = 22

    cnt_values = np.bitwise_and(2 ** TDC_CNT_BITS - 1, packets)
    cnt_overflow = (cnt_values == 0)
    maxvalues_a = (packets >> TDC_CNT_BITS).astype(np.uint16)
    event_a = (maxvalues_a != 0)

    # track counter overflows and construct timestamp array
    times_out_a = np.zeros(np.count_nonzero(event_a), dtype=np.double)
    maxvalues_out_a = np.zeros(np.count_nonzero(event_a), dtype=np.uint16)
    idx_a = 0
    DT_cyc = 4e-9
    cnt_accum = 0
    for i in range(packets.size):
        cnt_accum += 2**TDC_CNT_BITS * cnt_overflow[i]  # add counter length on overflow
        cnt_value = cnt_values[i]

        if event_a[i]:
            times_out_a[idx_a] = (cnt_accum + cnt_value) * DT_cyc
            maxvalues_out_a[idx_a] = maxvalues_a[i]
            idx_a += 1

    return times_out_a, maxvalues_out_a


class Digitizer2Mixin(object):
    """
    Mixin class for digitizer2 firmware.
    """

    class TriggerSource(IntEnum):
        """
        Trigger sources

        ============ =======================
        item         description
        ============ =======================
        CNT_OVERFLOW counter overflow
        D1_RISING    rising edge on D1
        D1_FALLING   falling edge on D1
        D2_RISING    rising edge on D2
        D2_FALLING   falling edge on D2
        A_MAXFOUND   maximum found (analog)
        NONE         no trigger
        ============ =======================
        """
        CNT_OVERFLOW = 0
        D1_RISING = 1
        D1_FALLING = 2
        D2_RISING = 3
        D2_FALLING = 4
        A_MAXFOUND = 5
        NONE = 6

    class AcqMode(IntEnum):
        """
        Acquisition modes

        ========  ======================
        item      description
        ========  ======================
        RAW       raw acquisition mode
        TDC       tdc mode
        MAXFIND   peak maximum mode
        ========  ======================
        """
        RAW = 0
        TDC = 2
        MAXFIND = 3

    def get_version(self):
        value = (self.read_reg(0, 3)) << 16 | (self.read_reg(0, 4))
        day = (value >> 27) & 0b11111
        month = (value >> 23) & 0b1111
        year = (value >> 17) & 0b111111
        hour = (value >> 12) & 0b11111
        minute = (value >> 6) & 0b111111
        second = (value >> 0) & 0b111111
        return year, month, day, hour, minute, second

    def get_status(self):
        return self.__status_to_dict(self.read_reg(*REG_STATUS))

    @staticmethod
    def __status_to_dict(status_val):
        status_str = "s_reset, s_wait_ready, s_waittrig, s_buffering, s_done".split(", ")[status_val]
        return {
            "acq_state": status_str
        }

    ###################################################

    def _read_reg_bit(self, addr, port, bit):
        value = self.read_reg(addr, port)
        return bool(value & (1 << bit))

    def _write_reg_bit(self, addr, port, bit, enabled):
        value = self.read_reg(addr, port)
        if enabled:
            value |= (1 << bit)
        else:
            value &= ~(1 << bit)
        self.write_reg(addr, port, value)

    def get_config_bit(self, bit):
        return self._read_reg_bit(REG_CONFIG[0], REG_CONFIG[1], bit)

    def set_config_bit(self, bit, enabled):
        self._write_reg_bit(REG_CONFIG[0], REG_CONFIG[1], bit, enabled)

    ###################################################

    def fpga_temperature(self):
        return self.read_reg(0, 6)

    ###################################################

    def adc_power(self, enabled):
        """
        Enable power to the analog circuit.
        """
        self.set_config_bit(1, enabled)

    ###################################################

    def _adc_program(self, addr, value):
        self.write_reg(PORT_ADCPROG, 0, addr)
        self.write_reg(PORT_ADCPROG, 1, value)

    def _adc_program_read(self, addr):
        wr_addr = addr | (1 << 7)
        self.write_reg(PORT_ADCPROG, 0, wr_addr)
        time.sleep(0.01)
        return self.read_reg(PORT_ADCPROG, 0)

    def _adc_program_test(self, pattern="toggle2"):
        # TODO: high perf. mode must be disabled when using test pattern
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
            self._adc_program(0x3c + i, pattern_words[i])

    ###################################################

    def _adc_device_enable(self, enabled):
        self.set_config_bit(3, enabled)

    def _adc_device_reset(self, enabled):
        self.set_config_bit(2, enabled)

    def _adc_program_autocorr_strobe(self):
        self._adc_program(0x03, 0b0100101100011000)
        self._adc_program(0x03, 0b0000101100011000)

    def _adc_program_highperf(self, enabled):
        value = 0b1000000000000010 if enabled else 0b1000000000000000
        self._adc_program(0x1, value)

    def adc_temperature(self):
        """
        Read and return the ADC device temperature

        :return: temperature in celsius
        """
        return self._adc_program_read(0x2b)

    def _adc_device_init_regs(self):
        self._adc_program(0x00, 0b0000000000000000)  # no decimation, no filter
        self._adc_program(0x01, 0b1000000000000010)  # corr en, fmt int12, hp mode1
        self._adc_program(0x0e, 0b0000000000000000)  # no sync
        self._adc_program(0x0f, 0b0000000000000000)  # no sync, 1.0V vref
        self._adc_program(0x38, 0b1111111111011111)  # hp mode2, bias en, no sync, lp mode
        self._adc_program(0x3a, 0b1101100000011011)  # 3.5mA LVDS current
        self._adc_program(0x66, 0b0000111111111111)  # LVDS output bus power (disable unused)

    def adc_device_enable(self, enabled):
        """
        Enable and initialize the onboard ADC.

        Analog power must be enabled before initializing the ADC.
        """

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
            # reset sampling instance (iserdes elements)
            self._sampling_rst()

    def _sampling_rst(self):
        self.set_config_bit(4, True)
        self.set_config_bit(4, False)

    def _set_acq_conf_bit(self, bit, enabled):
        self._write_reg_bit(REG_CONFIG_ACQ[0], REG_CONFIG_ACQ[1], bit, enabled)

    def _get_acq_conf(self):
        return self.read_reg(REG_CONFIG_ACQ[0], REG_CONFIG_ACQ[1])

    def acq_reset(self, enable):
        """
        Reset acquisition.

        An active reset will clear the internal buffer and reset the
        acquisition logic. After clearing the reset, the device will wait for
        the configured trigger condition and start recording data.
        """
        self._set_acq_conf_bit(0, enable)

    def acq_stop(self):
        """
        Stop acquisition manually.
        """
        self._set_acq_conf_bit(1, True)
        self._set_acq_conf_bit(1, False)

    def acq_mode(self, mode):
        """
        Set acquisition mode for next acquisition.

        For available acquisition mode options see :class:`AcqMode` enum.

        :param mode: acquisition mode
        """
        mode = int(mode)
        self._set_acq_conf_bit(2, mode & 0b01)
        self._set_acq_conf_bit(3, mode & 0b10)

    def _acq_mode_selected(self):
        return (self._get_acq_conf() >> 2) & 0b11

    def acq_start_trig_src(self, trig_source):
        """
        Set the start trigger source for acquisition.

        For available trigger source options see :class:`TriggerSource` enum.

        :param trig_source: trigger source
        """
        trig_source = int(trig_source)
        self._set_acq_conf_bit(4, trig_source & 0b001)
        self._set_acq_conf_bit(5, trig_source & 0b010)
        self._set_acq_conf_bit(6, trig_source & 0b100)

    def acq_stop_trig_src(self, trig_source):
        """
        Set the stop trigger source for acquisition.

        For available trigger source options see :class:`TriggerSource` enum.

        :param trig_source: trigger source
        """
        trig_source = int(trig_source)
        self._set_acq_conf_bit(7, trig_source & 0b001)
        self._set_acq_conf_bit(8, trig_source & 0b010)
        self._set_acq_conf_bit(9, trig_source & 0b100)

    def acq_buffer_count(self):
        """
        Return the number of words in the acquisition buffer.

        :return: number of words in buffer
        """
        return 2 * self.read_reg(PORT_ACQBUF, 0)

    def acq_buffer_read_raw(self):
        """
        Read the acquisition buffer.

        This returns the unmodified data from the device.

        :return: acquisition raw data
        """
        # read buffer
        n = self.acq_buffer_count()
        data = self.read_reg_n(PORT_ACQBUF, 1, n)
        return data

    def acq_buffer_read(self):
        """
        Read the acquisition buffer.

        This returns the data from the last acquisition.
        The data is parsed according to the data selection setting.

        :return: acquisition data
        """
        data = self.acq_buffer_read_raw()
        mode_selected = self._acq_mode_selected()
        if mode_selected == Digitizer2Mixin.AcqMode.RAW:
            return parse_mode0(data)
        elif mode_selected == Digitizer2Mixin.AcqMode.TDC:
            return parse_mode2(data)
        elif mode_selected == Digitizer2Mixin.AcqMode.MAXFIND:
            return parse_mode3(data)
        else:
            return data

    def maxfind_threshold(self, value):
        """
        Set threshold for maximum detection.

        :param value: threshold given in ADC units
        """
        value_u16 = int(np.int16(value).view(np.uint16))
        self.write_reg(REG_A_THRESHOLD[0], REG_A_THRESHOLD[1], value_u16)

    def analog_average(self, n):
        """
        Set window length of the analog moving average filter.

        The window length is n+1.

        :param n: window length parameter, range 0 to 2
        """
        assert 0 <= value <= 2
        self.set_config_bit(13, n & 0b01)
        self.set_config_bit(14, n & 0b10)

    def analog_invert(self, invert):
        """
        Set analog input polarity.

        This allows to invert the analog signal internally for detecting negative pulses.

        :param invert: enable/disable signal inverter
        """
        self.set_config_bit(15, invert)

    ###################################################

    # TODO: functions for testing ram

    def ram_buffer_init(self):
        for i in range(8):
            self.ram_buffer_write(i, i+1)

    def ram_buffer_write(self, i, word):
        assert i < 8
        self.write_reg(PORT_RAM, i, word)

    def ram_buffer_read(self):
        return [self.read_reg(PORT_RAM, i) for i in range(8)]

    def ram_write_addr(self, addr):
        self.write_reg(PORT_RAM, 8, addr & 0xffff)
        self.write_reg(PORT_RAM, 9, (addr >> 16) & 0x0fff)

    def ram_write_cmd(self):
        self.write_reg(PORT_RAM, 10, 0)

    def ram_read_cmd(self):
        self.write_reg(PORT_RAM, 10, 1)

