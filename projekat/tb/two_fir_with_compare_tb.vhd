library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use work.txt_util.all;
use work.util_pkg.all;

entity tb_two_fir is
    generic(in_out_data_width : natural := 24;
            fir_ord : natural := 5);
--  Port ( );
end tb_two_fir;

architecture Behavioral of tb_two_fir is
    constant period : time := 20 ns;
    signal clk_i_s : std_logic;
    file input_test_vector : text open read_mode is "C:\Users\Korisnik\Desktop\DSONG\projekat\data\input.txt";
    file output_check_vector : text open read_mode is "C:\Users\Korisnik\Desktop\DSONG\projekat\data\expected.txt";
    file input_coef : text open read_mode is "C:\Users\Korisnik\Desktop\DSONG\projekat\data\coef.txt";
    signal data_i_s : std_logic_vector(in_out_data_width-1 downto 0);
    signal data_o_s : std_logic_vector(in_out_data_width-1 downto 0);
    signal coef_addr_i_s : std_logic_vector(log2c(fir_ord)-1 downto 0);
    signal coef_i_s : std_logic_vector(in_out_data_width-1 downto 0);
    signal we_i_s : std_logic;
    signal error_o_s : std_logic;
    
    signal start_check : std_logic := '0';

begin

    uut_fir_filter:
    entity work.two_fir_with_compare(behavioral)
    generic map(fir_ord=>fir_ord,
                input_data_width=>in_out_data_width,
                output_data_width=>in_out_data_width)
    port map(clk_in=>clk_i_s,
             we_in=>we_i_s,
             coef_in=>coef_i_s,
             coef_addr_in=>coef_addr_i_s,
             data_in=>data_i_s,
             data_out=>data_o_s,
             error_out => error_o_s);

    clk_process:
    process
    begin
        clk_i_s <= '0';
        wait for period/2;
        clk_i_s <= '1';
        wait for period/2;
    end process;
    
    stim_process:
    process
        variable tv : line;
    begin
        --upis koeficijenata
        data_i_s <= (others=>'0');
        wait until falling_edge(clk_i_s);
        for i in 0 to fir_ord loop
            we_i_s <= '1';
            coef_addr_i_s <= std_logic_vector(to_unsigned(i,log2c(fir_ord)));
            readline(input_coef,tv);
            coef_i_s <= to_std_logic_vector(string(tv));
            wait until falling_edge(clk_i_s);
        end loop;
        --ulaz za filtriranje
        while not endfile(input_test_vector) loop
            readline(input_test_vector,tv);
            data_i_s <= to_std_logic_vector(string(tv));
            wait until falling_edge(clk_i_s);
            start_check <= '1';
        end loop;
        start_check <= '0';
        report "verification done!" severity failure;
    end process;
    
        check_process:
        process
            variable check_v : line;
            variable tmp : std_logic_vector(in_out_data_width-1 downto 0);
        begin
            wait until start_check = '1';
            -- preskoci pipeline latenciju (= fir_ord taktova) pre pocetka poredjenja
            for i in 1 to fir_ord - 2 loop
                wait until rising_edge(clk_i_s);
            end loop;
            while(true) loop
                wait until rising_edge(clk_i_s);
                exit when endfile(output_check_vector);
                readline(output_check_vector, check_v);
                tmp := to_std_logic_vector(string(check_v));
                if(abs(signed(tmp) - signed(data_o_s)) > "000000000000000000000111") then
                    report "result mismatch! expected=" & hstr(tmp) & " got=" & hstr(data_o_s) severity error;
                end if;
            end loop;
            report "check process done!" severity note;
        end process;

end Behavioral;