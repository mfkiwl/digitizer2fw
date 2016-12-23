-------------------------------------------------------------------------------
-- FT2232 Communication Interface
--
-- (De)serializes data to/from USB interface for writing/reading registers
--
-- Author: Peter Würtz, TU Kaiserslautern (2016)
-- Distributed under the terms of the GNU General Public License Version 3.
-- The full license is in the file COPYING.txt, distributed with this software.
-------------------------------------------------------------------------------

library unisim;
use unisim.vcomponents.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.communication_pkg.all;

entity ft2232_communication is
    port (
        clk: in std_logic;
        rst: in std_logic;
        error: out std_logic;
        -- application bus interface
        slave_addr: out unsigned(5 downto 0);
        slave_port: out unsigned(5 downto 0);
        comm_to_slave: out comm_to_slave_t;
        comm_from_slave: in comm_from_slave_t;
        -- ftdi interface
        usb_clk: in std_logic;
        usb_oe_n: out std_logic;
        usb_rd_n: out std_logic;
        usb_wr_n: out std_logic;
        usb_rxf_n: in std_logic;
        usb_txe_n: in std_logic;
        usb_d: inout std_logic_vector(7 downto 0)
    );
end ft2232_communication;

architecture ft2232_communication_arch of ft2232_communication is
    
    component ft2232fifo
        port (
            -- ftdi interface
            usb_clk: in std_logic;
            usb_oe_n: out std_logic;
            usb_rd_n: out std_logic;
            usb_wr_n: out std_logic;
            usb_rxf_n: in std_logic;
            usb_txe_n: in std_logic;
            usb_d: inout std_logic_vector(7 downto 0);
            -- application/fifo interface
            rst: in std_logic;
            fifo_in_wr_en: out std_logic;
            fifo_in_full: in std_logic;
            fifo_in_data: out std_logic_vector(7 downto 0);
            fifo_out_rd_en: out std_logic;
            fifo_out_empty: in std_logic;
            fifo_out_data: in std_logic_vector(7 downto 0)
        );
    end component;

    component fifo_16_to_8
        port (
            rst: in std_logic;
            wr_clk: in std_logic;
            rd_clk: in std_logic;
            din: in std_logic_vector(15 downto 0);
            wr_en: in std_logic;
            rd_en: in std_logic;
            dout: out std_logic_vector(7 downto 0);
            full: out std_logic;
            empty: out std_logic
        );
    end component;

    component fifo_8_to_16
        port (
            rst: in std_logic;
            wr_clk: in std_logic;
            rd_clk: in std_logic;
            din: in std_logic_vector(7 downto 0);
            wr_en: in std_logic;
            rd_en: in std_logic;
            dout: out std_logic_vector(15 downto 0);
            full: out std_logic;
            empty: out std_logic
        );
    end component;
    
    component communication
        port (
            clk: in std_logic;
            rst: in std_logic;
            error: out std_logic;
            -- application bus interface
            slave_addr: out unsigned(5 downto 0);
            slave_port: out unsigned(5 downto 0);
            comm_to_slave: out comm_to_slave_t;
            comm_from_slave: in comm_from_slave_t;
            -- fifo interface
            fifo_out_wr_en: out std_logic;
            fifo_out_full: in std_logic;
            fifo_out_data: out std_logic_vector(COMM_BUS_WIDTH-1 downto 0);
            fifo_in_rd_en: out std_logic;
            fifo_in_empty: in std_logic;
            fifo_in_data: in std_logic_vector(COMM_BUS_WIDTH-1 downto 0)
        );
    end component;

    signal fifo_from_usb_rd, fifo_from_usb_empty: std_logic;
    signal fifo_from_usb_wr, fifo_from_usb_full: std_logic;
    signal fifo_to_usb_rd, fifo_to_usb_empty: std_logic;
    signal fifo_to_usb_wr, fifo_to_usb_full: std_logic;
    signal fifo_to_usb_dout, fifo_from_usb_din: std_logic_vector(7 downto 0);
    signal fifo_to_usb_din, fifo_from_usb_dout: std_logic_vector(15 downto 0);

begin

communication_inst: communication
port map (
    clk => clk,
    rst => rst,
    error => error,
    -- application register interface
    slave_addr => slave_addr,
    slave_port => slave_port,
    comm_to_slave => comm_to_slave,
    comm_from_slave => comm_from_slave,
    -- fifo interface
    fifo_out_wr_en => fifo_to_usb_wr,
    fifo_out_full => fifo_to_usb_full,
    fifo_out_data => fifo_to_usb_din,
    fifo_in_rd_en => fifo_from_usb_rd,
    fifo_in_empty => fifo_from_usb_empty,
    fifo_in_data => fifo_from_usb_dout
);

ft2232fifo_inst: ft2232fifo
port map (
    -- ftdi interface
    usb_clk => usb_clk,
    usb_oe_n => usb_oe_n,
    usb_rd_n => usb_rd_n,
    usb_wr_n => usb_wr_n,
    usb_rxf_n => usb_rxf_n,
    usb_txe_n => usb_txe_n,
    usb_d => usb_d,
    -- application/fifo interface
    rst => rst,
    fifo_in_wr_en => fifo_from_usb_wr,
    fifo_in_full => fifo_from_usb_full,
    fifo_in_data => fifo_from_usb_din,
    fifo_out_rd_en => fifo_to_usb_rd,
    fifo_out_empty => fifo_to_usb_empty,
    fifo_out_data => fifo_to_usb_dout
);

fifo_to_usb: fifo_16_to_8
port map (
    rst => rst,
    wr_clk => clk,
    rd_clk => usb_clk,
    din => fifo_to_usb_din,
    wr_en => fifo_to_usb_wr,
    rd_en => fifo_to_usb_rd,
    dout => fifo_to_usb_dout,
    full => fifo_to_usb_full,
    empty => fifo_to_usb_empty
);

fifo_from_usb: fifo_8_to_16
port map (
    rst => rst,
    wr_clk => usb_clk,
    rd_clk => clk,
    din => fifo_from_usb_din,
    wr_en => fifo_from_usb_wr,
    rd_en => fifo_from_usb_rd,
    dout => fifo_from_usb_dout,
    full => fifo_from_usb_full,
    empty => fifo_from_usb_empty
);

end ft2232_communication_arch;


