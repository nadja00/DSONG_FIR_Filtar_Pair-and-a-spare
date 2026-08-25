%% generate_golden_vectors.m
% Generise coef.txt, input.txt i expected.txt u formatu koji ocekuje
% VHDL testbench (tb.vhd / top_tb.vhd / two_fir_with_compare_tb.vhd):
%   - 24-bitni signed fixed-point, format Q1.23 (1 sign bit + 23 fractional)
%   - jedan binarni string po liniji, bez razmaka, bez tacke
%
% Format je izveden iz fir_param.vhd / mac.vhd:
%   - MAC:    signed(coef) * signed(data) akumulirano u 48-bitni registar (Q2.46)
%   - izlaz:  bitovi (46 downto 23) -> floor(akumulator / 2^23), BEZ rundovanja
%             i BEZ saturacije (samo se sece gornji bit i donjih 23 bita)
%
% Ako promenis fir_ord ili sirinu podataka u VHDL-u, promeni i ovde.

clear; clc;

%% ------------------- Parametri (moraju odgovarati VHDL generic-ima) -------------------
N_BITS      = 24;              % input_data_width / output_data_width
FRAC_BITS   = N_BITS - 1;      % 23 -> Q1.23 format
SCALE       = 2^FRAC_BITS;     % faktor skaliranja za kvantizaciju
FIR_ORD     = 5;               % fir_ord generic -> broj koeficijenata = fir_ord + 1
N_TAPS      = FIR_ORD + 1;
N_SAMPLES   = 4096;             % broj ulaznih odbiraka (za top_tb.vhd = RAM_DEPTH!)
OUT_DIR     = 'data';           % folder gde ce fajlovi biti sacuvani

if ~exist(OUT_DIR, 'dir')
    mkdir(OUT_DIR);
end

%% ------------------- 1) Generisanje i kvantizacija koeficijenata -------------------
% Primer: simetrican lowpass FIR sa fir1 (6 koeficijenata za fir_ord=5)
b = fir1(FIR_ORD, 0.3);        % normalizovana granicna frekvencija 0.3*fs/2
b = b / max(abs(b)) * 0.9;     % skaliranje da ostane u opsegu [-1,1) sa margom

coef_int = quantize_q123(b, SCALE, N_BITS);   % celobrojne (int64) kvantizovane vrednosti

%% ------------------- 2) Generisanje i kvantizacija ulaznih odbiraka -------------------
rng(42);                                       % fiksni seed za reproduktivnost
x = 0.5 * sin(2*pi*0.05*(0:N_SAMPLES-1)) + 0.05*randn(1, N_SAMPLES);
x = max(min(x, 0.99), -1);                     % osiguraj opseg [-1, 1)

input_int = quantize_q123(x, SCALE, N_BITS);

%% ------------------- 3) Racunanje "golden" izlaza -- ISTA aritmetika kao MAC -------------------
% Direktna FIR konvolucija u celobrojnoj (int64) aritmetici, bit-precizno
% kao mac.vhd + fir_param.vhd seckanje bitova.
expected_int = zeros(1, N_SAMPLES, 'int64');
shift_reg    = zeros(1, N_TAPS, 'int64');       % simulira pomeranje u FIR strukturi

for n = 1:N_SAMPLES
    shift_reg = [int64(input_int(n)), shift_reg(1:end-1)];
    acc = int64(0);
    for k = 1:N_TAPS
        acc = acc + int64(coef_int(k)) * shift_reg(k);   % Q1.23 * Q1.23 = Q2.46
    end
    % Bitovi (46 downto 23): aritmeticki desni shift za 23, bez rundovanja
    out_val = idivide(acc, int64(SCALE), 'floor');
    % Umotaj u 24-bitni dvokomplement (bez saturacije, tacno kao HW)
    expected_int(n) = wrap_to_nbits(out_val, N_BITS);
end

%% ------------------- 4) Upis u .txt fajlove (24-bitni binarni string po liniji) -------------------
write_bin_file(fullfile(OUT_DIR, 'coef.txt'),     coef_int,     N_BITS);
write_bin_file(fullfile(OUT_DIR, 'input.txt'),    input_int,    N_BITS);
write_bin_file(fullfile(OUT_DIR, 'expected.txt'), expected_int, N_BITS);

fprintf('Gotovo. Fajlovi su u folderu: %s\n', OUT_DIR);

%% ================= Pomocne funkcije =================
function q = quantize_q123(vals, scale, nbits)
    % Kvantizuje realne vrednosti u opsegu [-1,1) na Q1.23 celobrojni format,
    % sa rundovanjem i saturacijom (koristi se SAMO za ulaze/koeficijente,
    % ne za izlaz FIR-a koji mora vernije pratiti HW seckanje bez saturacije).
    maxv = 2^(nbits-1) - 1;
    minv = -2^(nbits-1);
    q = round(double(vals) * scale);
    q = max(min(q, maxv), minv);
    q = int64(q);
end

function wrapped = wrap_to_nbits(val, nbits)
    % Umotava celobrojnu vrednost u n-bitni dvokomplementni opseg
    % (modulo 2^n, bez saturacije) - isto sto VHDL radi pri seckanju bitova.
    m = int64(2)^nbits;
    wrapped = mod(val, m);
    wrapped(wrapped >= m/2) = wrapped(wrapped >= m/2) - m;
end

function bin_str = to_twos_complement_bin(val, nbits)
    % Konvertuje (mogucu negativnu) celobrojnu vrednost u n-bitni
    % dvokomplementni binarni string (samo '0'/'1', bez razmaka).
    m = 2^nbits;
    uval = mod(double(val), m);           % preslikaj negativne u [0, 2^n)
    bin_str = dec2bin(uval, nbits);
end

function write_bin_file(filename, values, nbits)
    fid = fopen(filename, 'w');
    if fid == -1
        error('Ne mogu da otvorim fajl za pisanje: %s', filename);
    end
    for i = 1:length(values)
        fprintf(fid, '%s\n', to_twos_complement_bin(values(i), nbits));
    end
    fclose(fid);
end
