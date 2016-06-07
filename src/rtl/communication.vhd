-------------------------------------------------------------------------------
-- Communication Interface
--
-- (De)serializes data to/from a FWFT FIFO interface for register read/writing
--
-- TODO: Document protocol
-------------------------------------------------------------------------------

library unisim;
use unisim.vcomponents.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.communication_pkg.all;

entity communication is
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
end communication;

architecture communication_arch of communication is

    -- protocol definitions
    constant cmd_reg_read: integer := 1;
    constant cmd_reg_write: integer := 2;
    constant cmd_reg_read_n: integer := 3;
    constant cmd_reg_write_n: integer := 4;
    
    -- state machine
    type fsm_state_t is (s_reset, s_idle,
                         s_write_reg_size, s_write_reg_data,
                         s_read_reg_size, s_read_reg_data);
    signal state, next_state: fsm_state_t;
    signal addr_int, next_addr_int: unsigned(5 downto 0);
    signal port_int, next_port_int: unsigned(5 downto 0);
    signal block_size, next_block_size: unsigned(15 downto 0);
begin
-------------------------------------------------------------------------------

-- register state
sync_proc: process(clk, rst)
begin
    if rising_edge(clk) then
        if rst = '1' then
            state <= s_reset;
        else
            state <= next_state;
            addr_int <= next_addr_int;
            port_int <= next_port_int;
            block_size <= next_block_size;
        end if;
    end if;
end process;

-- next state and output logic
next_state_decode: process(state, block_size, addr_int, port_int,
                           comm_from_slave,
                           fifo_in_empty, fifo_out_full, fifo_in_data)
    variable cmd: integer;
begin
    next_state <= state;
    next_addr_int <= addr_int;
    next_port_int <= port_int;
    next_block_size <= block_size;
    -- register interface (r/w)
    slave_addr <= addr_int;
    slave_port <= port_int;
    comm_to_slave.wr_req <= '0';
    comm_to_slave.rd_req <= '0';
    comm_to_slave.data_wr <= fifo_in_data;
    fifo_out_data <= comm_from_slave.data_rd;
    -- fifo interface (r/w)
    fifo_out_wr_en <= '0';
    fifo_in_rd_en <= '0';
    error <= '0';
    
    case state is
        when s_reset =>
            next_state <= s_idle;

        when s_idle =>
            -- wait for next command
            if fifo_in_empty = '0' then
                -- ack data from fifo
                fifo_in_rd_en <= '1';
                -- decode command bits
                cmd := to_integer(unsigned(fifo_in_data(15 downto 12)));
                case cmd is
                    when cmd_reg_read =>
                        next_state <= s_read_reg_data;
                        next_block_size <= to_unsigned(1, 16);
                    when cmd_reg_write =>
                        next_state <= s_write_reg_data;
                        next_block_size <= to_unsigned(1, 16);
                    when cmd_reg_read_n =>
                        next_state <= s_read_reg_size;
                    when cmd_reg_write_n =>
                        next_state <= s_write_reg_size;
                    when others =>
                        error <= '1';
                        next_state <= s_idle;
                end case;
                -- store slave address and port
                next_addr_int <= unsigned(fifo_in_data(11 downto 6));
                next_port_int <= unsigned(fifo_in_data(5 downto 0));
            end if;

        when s_write_reg_size =>
            -- read data block size from fifo
            if fifo_in_empty = '0' then
                fifo_in_rd_en <= '1';
                next_block_size <= unsigned(fifo_in_data);
                next_state <= s_write_reg_data;
            end if;

        when s_write_reg_data =>
            if fifo_in_empty = '0' then
                -- request write operation if fifo isn't empty
                comm_to_slave.wr_req <= '1';
                if comm_from_slave.wr_ack = '1' then
                    -- if accepted, ack data from fifo
                    fifo_in_rd_en <= '1';
                    next_block_size <= block_size - 1;
                    -- return to idle when next_block_size=0
                    if block_size = 1 then
                        next_state <= s_idle;
                    end if;
                end if;
            end if;

        when s_read_reg_size =>
            -- read data block size from fifo
            if fifo_in_empty = '0' then
                fifo_in_rd_en <= '1';
                next_block_size <= unsigned(fifo_in_data);
                next_state <= s_read_reg_data;
            end if;

        when s_read_reg_data =>
            if fifo_out_full = '0' then
                -- request read operation if fifo isn't full
                comm_to_slave.rd_req <= '1';
                if comm_from_slave.rd_ack = '1' then
                    -- if accepted, push data to fifo
                    fifo_out_wr_en <= '1';
                    next_block_size <= block_size - 1;
                    -- return to idle when next_block_size=0
                    if block_size = 1 then
                        next_state <= s_idle;
                    end if;
                end if;
            end if;

        when others =>
            error <= '1';
    end case;

end process;

end communication_arch;

