-------------------------------------------------------------------------------
-- Clock domain crossing circuit for slowly changing signals
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity slow_cdc_bit is
    port (
        clk: in std_logic;
        din: in std_logic;
        dout: out std_logic
    );
end slow_cdc_bit;

library ieee;
use ieee.std_logic_1164.all;

entity slow_cdc_bits is
    port (
        clk: in std_logic;
        din: in std_logic_vector;
        dout: out std_logic_vector
    );
end slow_cdc_bits;

---

architecture slow_cdc_bit_arch of slow_cdc_bit is
    signal d_async: std_logic := '0';
    signal d_meta: std_logic := '0';
    signal d_sync: std_logic := '0';
    
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of d_async : signal is "TRUE";
    attribute ASYNC_REG of d_meta : signal is "TRUE";
    attribute ASYNC_REG of d_sync : signal is "TRUE";
begin

d_async <= din;

process(clk)
begin
    if rising_edge(clk) then
        d_meta <= d_async;
        d_sync <= d_meta;
    end if;
end process;

dout <= d_sync;

end slow_cdc_bit_arch;


architecture slow_cdc_bits_arch of slow_cdc_bits is
begin

gen: for I in din'low to din'high generate
    sync_bit : entity work.slow_cdc_bit
    port map (
        clk => clk,
        din => din(I),
        dout => dout(I)
    );
end generate;

end slow_cdc_bits_arch;