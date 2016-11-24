library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package maxfinder_pkg is

    function log2ceil(x: natural) return natural;

    component maxfinder_base
    generic (
        N_WINDOW_LENGTH : natural;
        N_OUTPUTS : natural;
        N_SAMPLE_BITS : natural;
        SYNC_STAGE1: boolean := FALSE;
        SYNC_STAGE2: boolean := TRUE;
        SYNC_STAGE3: boolean := TRUE
    );
    port (
        clk : in std_logic;
        samples : in std_logic_vector( N_WINDOW_LENGTH * N_SAMPLE_BITS - 1 downto 0 );
        threshold : in std_logic_vector( N_SAMPLE_BITS - 1 downto 0 );
        max_found : out std_logic_vector( N_OUTPUTS - 1 downto 0 );
        max_pos : out std_logic_vector( N_OUTPUTS * log2ceil( N_WINDOW_LENGTH / N_OUTPUTS )- 1 downto 0 );
        max_adiff0 : out std_logic_vector( N_OUTPUTS * N_SAMPLE_BITS - 1 downto 0 );
        max_adiff1 : out std_logic_vector( N_OUTPUTS * N_SAMPLE_BITS - 1 downto 0 );
        max_sample0 : out std_logic_vector( N_OUTPUTS * N_SAMPLE_BITS - 1 downto 0 );
        max_sample1 : out std_logic_vector( N_OUTPUTS * N_SAMPLE_BITS - 1 downto 0 )
    );
    end component;

end maxfinder_pkg;

package body maxfinder_pkg is

function log2ceil(x: natural) return natural is
begin
    return natural(ceil(log2(real(x))));
end log2ceil;

end maxfinder_pkg;
