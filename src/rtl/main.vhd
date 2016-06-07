library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.communication_pkg.all;

entity top_level is
  Port ( 
--    DIN_N : in STD_LOGIC_VECTOR ( 1 downto 0 );
--    DIN : in STD_LOGIC_VECTOR ( 1 downto 0 );
    LED1 : out STD_LOGIC;
    LED2 : out STD_LOGIC;
    GCLK1 : in STD_LOGIC;
--    GPIO1_N : inout STD_LOGIC;
--    GPIO1 : inout STD_LOGIC;

    -- USB
    USB_D : inout STD_LOGIC_VECTOR ( 7 downto 0 );
    USB_WR : out STD_LOGIC;
    USB_TXE : in STD_LOGIC;
    USB_RXF : in STD_LOGIC;
    USB_RD : out STD_LOGIC;
    USB_OE : out STD_LOGIC;
    USB_CLKOUT : in STD_LOGIC;

    -- DRAM
    ddr3_dq : inout STD_LOGIC_VECTOR ( 15 downto 0 );
    ddr3_addr : out STD_LOGIC_VECTOR ( 13 downto 0 );
    ddr3_ba : out STD_LOGIC_VECTOR ( 2 downto 0 );
    ddr3_we_n : out STD_LOGIC;
    ddr3_reset_n : out STD_LOGIC;
    ddr3_ras_n : out STD_LOGIC;
    ddr3_cas_n : out STD_LOGIC;
    ddr3_odt : out STD_LOGIC_VECTOR ( 0 downto 0 );
    ddr3_cke : out STD_LOGIC_VECTOR ( 0 downto 0 );
    ddr3_ck_p : out STD_LOGIC_VECTOR ( 0 downto 0 );
    ddr3_ck_n : out STD_LOGIC_VECTOR ( 0 downto 0 );
    ddr3_dqs_p : inout STD_LOGIC_VECTOR ( 1 downto 0 );
    ddr3_dqs_n : inout STD_LOGIC_VECTOR ( 1 downto 0 )

    -- ADC
--    ADC_SAMPLE_CLK : out STD_LOGIC;
--    ADC_SAMPLE_CLK_N : out STD_LOGIC
--    ADC_DA : in STD_LOGIC_VECTOR ( 11 downto 0 );
--    ADC_DA_N : in STD_LOGIC_VECTOR ( 11 downto 0 );
--    ADC_DACLK_N : in STD_LOGIC;
--    ADC_DACLK : in STD_LOGIC;
--    ADC_OVRA : in STD_LOGIC;
--    ADC_OVRA_N : in STD_LOGIC;
--    ADC_SRESET : out STD_LOGIC;
--    ADC_SDIO : inout STD_LOGIC;
--    ADC_SDENB : out STD_LOGIC;
--    ADC_SCLK : out STD_LOGIC
  );
end top_level;

architecture top_level_arch of top_level is
    
    component clk_core_usb
    port (
        clk_in: in std_logic;
        clk_core_out: out std_logic;
        clk_usb_out: out std_logic;
        clk_to_ddr_sys: out std_logic;
        clk_to_ddr_ref: out std_logic
    );
    end component;
    signal clk_main: std_logic;
    signal clk_core, clk_usb, clk_to_ddr_sys, clk_to_ddr_ref: std_logic;

    component fifo_16
    port (
        clk: IN STD_LOGIC;
        srst: IN STD_LOGIC;
        din: IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        wr_en: IN STD_LOGIC;
        rd_en: IN STD_LOGIC;
        dout: OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
        full: OUT STD_LOGIC;
        empty: OUT STD_LOGIC;
        data_count: OUT STD_LOGIC_VECTOR(10 DOWNTO 0)
    );
    end component;
    signal fifo_echo_full: std_logic;
    signal fifo_echo_empty: std_logic;
    signal fifo_echo_rd_en: std_logic;
    signal fifo_echo_wr_en: std_logic;
    signal fifo_echo_count: std_logic_vector(10 downto 0);
    signal fifo_echo_dout: std_logic_vector(15 downto 0);
    signal fifo_echo_din: std_logic_vector(15 downto 0);
  
    component ddr3_controller
    port (
        ddr3_dq       : inout std_logic_vector(15 downto 0);
        ddr3_dqs_p    : inout std_logic_vector(1 downto 0);
        ddr3_dqs_n    : inout std_logic_vector(1 downto 0);
        ddr3_addr     : out   std_logic_vector(13 downto 0);
        ddr3_ba       : out   std_logic_vector(2 downto 0);
        ddr3_ras_n    : out   std_logic;
        ddr3_cas_n    : out   std_logic;
        ddr3_we_n     : out   std_logic;
        ddr3_reset_n  : out   std_logic;
        ddr3_ck_p     : out   std_logic_vector(0 downto 0);
        ddr3_ck_n     : out   std_logic_vector(0 downto 0);
        ddr3_cke      : out   std_logic_vector(0 downto 0);
        ddr3_odt      : out   std_logic_vector(0 downto 0);
        app_addr                  : in    std_logic_vector(27 downto 0);
        app_cmd                   : in    std_logic_vector(2 downto 0);
        app_en                    : in    std_logic;
        app_wdf_data              : in    std_logic_vector(127 downto 0);
        app_wdf_end               : in    std_logic;
        app_wdf_wren              : in    std_logic;
        app_rd_data               : out   std_logic_vector(127 downto 0);
        app_rd_data_end           : out   std_logic;
        app_rd_data_valid         : out   std_logic;
        app_rdy                   : out   std_logic;
        app_wdf_rdy               : out   std_logic;
        app_sr_req                : in    std_logic;
        app_ref_req               : in    std_logic;
        app_zq_req                : in    std_logic;
        app_sr_active             : out   std_logic;
        app_ref_ack               : out   std_logic;
        app_zq_ack                : out   std_logic;
        ui_clk                    : out   std_logic;
        ui_clk_sync_rst           : out   std_logic;
        init_calib_complete       : out   std_logic;
        -- System Clock Ports
        sys_clk_i                      : in    std_logic;
        -- Reference Clock Ports
        clk_ref_i                                : in    std_logic;
        device_temp_o                    : out std_logic_vector(11 downto 0);
      sys_rst                     : in    std_logic
    );
    end component;
    signal ram_init_calib_complete: std_logic;
    signal ram_sys_rst: std_logic := '1';
    signal ram_app_clk: std_logic;
    signal ram_app_rdy: std_logic;
    signal ram_app_cmd: std_logic_vector(2 downto 0);
    signal ram_app_en: std_logic;
    signal ram_app_rd_data: std_logic_vector(127 downto 0);
    signal ram_last_rd_data: std_logic_vector(127 downto 0) := (others => '0');
    signal ram_app_rd_data_valid: std_logic;
    signal ram_app_wdf_rdy: std_logic;
    signal ram_app_wdf_data: std_logic_vector(127 downto 0);
    signal ram_app_wdf_wren: std_logic;
    signal ram_app_wdf_end: std_logic;

    component ft2232_communication
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
    end component;
    
    -- Communitation signals
    --signal comm_error: std_logic;
    signal comm_addr: unsigned(5 downto 0);
    signal comm_port: unsigned(5 downto 0);
    signal comm_to_slave, comm_to_global, comm_to_echo, comm_to_ram: comm_to_slave_t;
    signal comm_from_slave, comm_from_global, comm_from_echo, comm_from_ram: comm_from_slave_t;
    
    signal global_status: std_logic_vector(2 downto 0);
    
    constant VERSION: natural := 106;

begin

clk_main <= ram_app_clk;

clk_core_usb_inst: clk_core_usb
port map (
    clk_in => USB_CLKOUT,
    clk_core_out => clk_core,
    clk_usb_out => clk_usb,
    clk_to_ddr_sys => clk_to_ddr_sys,
    clk_to_ddr_ref => clk_to_ddr_ref
);

ddr3_controller_inst : ddr3_controller
port map (
    -- Memory interface ports
    ddr3_addr                      => ddr3_addr,
    ddr3_ba                        => ddr3_ba,
    ddr3_cas_n                     => ddr3_cas_n,
    ddr3_ck_n                      => ddr3_ck_n,
    ddr3_ck_p                      => ddr3_ck_p,
    ddr3_cke                       => ddr3_cke,
    ddr3_ras_n                     => ddr3_ras_n,
    ddr3_reset_n                   => ddr3_reset_n,
    ddr3_we_n                      => ddr3_we_n,
    ddr3_dq                        => ddr3_dq,
    ddr3_dqs_n                     => ddr3_dqs_n,
    ddr3_dqs_p                     => ddr3_dqs_p,
    init_calib_complete            => ram_init_calib_complete,
    ddr3_odt                       => ddr3_odt,
    -- Application interface ports
    app_addr                       => (others => '0'),
    app_cmd                        => ram_app_cmd,
    app_en                         => ram_app_en,
    app_wdf_data                   => ram_app_wdf_data,
    app_wdf_end                    => ram_app_wdf_end,
    app_wdf_wren                   => ram_app_wdf_wren,
    app_rd_data                    => ram_app_rd_data,
    app_rd_data_end                => open,
    app_rd_data_valid              => ram_app_rd_data_valid,
    app_rdy                        => ram_app_rdy,
    app_wdf_rdy                    => ram_app_wdf_rdy,
    app_sr_req                     => '0',
    app_ref_req                    => '0',
    app_zq_req                     => '0',
    app_sr_active                  => open,
    app_ref_ack                    => open,
    app_zq_ack                     => open,
    ui_clk                         => ram_app_clk,
    ui_clk_sync_rst                => open,
    -- System Clock Ports
    sys_clk_i                      => clk_to_ddr_sys,
    -- Reference Clock Ports
    clk_ref_i                      => clk_to_ddr_ref,
    device_temp_o                  => open,
    sys_rst                        => ram_sys_rst
);

ft2232_communication_inst: ft2232_communication
port map (
    clk => clk_main,
    rst => '0',
    error => open,
    -- application register interface
    slave_addr => comm_addr,
    slave_port => comm_port,
    comm_to_slave => comm_to_slave,
    comm_from_slave => comm_from_slave,
    -- ftdi interface
    usb_clk => clk_usb,
    usb_oe_n => USB_OE,
    usb_rd_n => USB_RD,
    usb_wr_n => USB_WR,
    usb_rxf_n => USB_RXF,
    usb_txe_n => USB_TXE,
    usb_d => USB_D
);

-- communication slave select process
slave_select: process(comm_addr, comm_to_slave, comm_from_global, comm_from_echo, comm_from_ram)
    constant not_selected: comm_to_slave_t := (rd_req => '0', wr_req => '0', data_wr => (others => '-'));
begin
    -- do not pass rd/wr requests to unselected slaves, pass ones from null selection
    comm_to_global <= not_selected;
    comm_to_echo <= not_selected;
    comm_to_ram <= not_selected;
    comm_from_slave <= (rd_ack => '1', wr_ack => '1', data_rd => (others => '1'));
    -- select communication slave based on comm_addr
    case to_integer(comm_addr) is
        when 0 =>
            comm_to_global <= comm_to_slave;
            comm_from_slave <= comm_from_global;
        when 1 =>
            comm_to_echo <= comm_to_slave;
            comm_from_slave <= comm_from_echo;
        when 2 =>
            comm_to_ram <= comm_to_slave;
            comm_from_slave <= comm_from_ram;
        when others =>
            null;
    end case;
end process;

-- read global registers
process(comm_to_global, comm_port, global_status)
begin
    comm_from_global <= (rd_ack => '1', wr_ack => '1', data_rd => (others => '0'));

    case to_integer(comm_port) is
        when 1 =>
            comm_from_global.data_rd(global_status'range) <= global_status;
        when 3 =>
            comm_from_global.data_rd <= std_logic_vector(to_unsigned(VERSION, 16));
        when others =>
            null;
    end case;
end process;

-- write global registers
global_registers: process(clk_main)
begin
    if rising_edge(clk_main) then
        -- update status registers
        global_status <= ram_app_wdf_rdy & ram_app_rdy & ram_init_calib_complete;
        
        -- register command flags from usb
        if comm_to_global.wr_req = '1' and to_integer(comm_port) = 0 then
            LED1 <= comm_to_global.data_wr(0);
            ram_sys_rst <= comm_to_global.data_wr(0);
        end if;
    end if;
end process;
LED2 <= ram_app_rdy;

-- read/write echo buffer
process(comm_to_echo, comm_port, fifo_echo_empty, fifo_echo_full, fifo_echo_dout, fifo_echo_count)
begin
    comm_from_echo <= (rd_ack => '1', wr_ack => '1', data_rd => (others => '0'));
    fifo_echo_rd_en <= '0';
    fifo_echo_wr_en <= '0';
    fifo_echo_din <= comm_to_echo.data_wr;

    case to_integer(comm_port) is
        when 0 =>
            -- read fifo size
            comm_from_echo.data_rd(fifo_echo_count'range) <= fifo_echo_count;
        when 1 =>
            -- read fifo data word
            fifo_echo_rd_en <= comm_to_echo.rd_req;
            comm_from_echo.rd_ack <= not fifo_echo_empty;
            comm_from_echo.data_rd <= fifo_echo_dout;
            -- write fifo data word
            fifo_echo_wr_en <= comm_to_echo.wr_req;
            comm_from_echo.wr_ack <= not fifo_echo_full;
        when others =>
            null;
    end case;
end process;

-- ram comm slave
process(ram_app_clk)
    constant RAM_CMD_WR: std_logic_vector(2 downto 0) := "000";
    constant RAM_CMD_RD: std_logic_vector(2 downto 0) := "001";
    variable n: integer;
begin
    if rising_edge(ram_app_clk) then
        -- default, no ram activity, no comm answer
        comm_from_ram <= (rd_ack => '0', wr_ack => '0', data_rd => (others => '-'));
        ram_app_en <= '0';
        ram_app_cmd <= ram_app_cmd;
        ram_app_wdf_wren <= '0';
        ram_app_wdf_end <= '0';

        n := to_integer(comm_port);
        if (n < 8) then
            -- write to ram_wr buffer or read from last ram word
            if comm_to_ram.wr_req = '1' then
                -- write word to ram write buffer
                ram_app_wdf_data(((n+1)*16-1) downto (n*16)) <= comm_to_ram.data_wr;
                comm_from_ram.wr_ack <= '1';
            elsif comm_to_ram.rd_req = '1' then
                -- read word from ram read buffer
                comm_from_ram.data_rd <= ram_last_rd_data(((n+1)*16-1) downto (n*16));
                comm_from_ram.rd_ack <= '1';
            end if;
        else
            -- send read or write command to ram
            if comm_to_ram.wr_req = '1' then
                comm_from_ram.wr_ack <= '1';
                if comm_to_ram.data_wr(0) = '0' then
                    -- ram write command
                    ram_app_wdf_wren <= '1';
                    ram_app_wdf_end <= '1';
                    ram_app_cmd <= RAM_CMD_WR;
                    ram_app_en <= '1';
                else
                    -- ram read command
                    ram_app_cmd <= RAM_CMD_RD;
                    ram_app_en <= '1';
                end if;
            end if;
        end if;
        
        -- store last word from ram
        if (ram_app_rd_data_valid = '1') then
            ram_last_rd_data <= ram_app_rd_data;
        end if;
    end if;
end process;

fifo_echo: fifo_16
port map (
    clk => clk_main,
    srst => '0',
    full => fifo_echo_full,
    empty => fifo_echo_empty,
    din => fifo_echo_din,
    dout => fifo_echo_dout,
    wr_en => fifo_echo_wr_en,
    rd_en => fifo_echo_rd_en,
    data_count => fifo_echo_count
);

end top_level_arch;