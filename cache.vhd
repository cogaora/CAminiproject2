LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY cache IS
	GENERIC (
		ram_size : INTEGER := 32768;
		cache_size : INTEGER := 32
	);
	PORT (
		clock : IN STD_LOGIC;
		reset : IN STD_LOGIC;

		-- Avalon interface --
		s_addr : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		s_read : IN STD_LOGIC;
		s_readdata : OUT STD_LOGIC_VECTOR (31 DOWNTO 0);
		s_write : IN STD_LOGIC;
		s_writedata : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		s_waitrequest : OUT STD_LOGIC;

		m_addr : OUT INTEGER RANGE 0 TO ram_size - 1;
		m_read : OUT STD_LOGIC;
		m_readdata : IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		m_write : OUT STD_LOGIC;
		m_writedata : OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
		m_waitrequest : IN STD_LOGIC
	);
END cache;

ARCHITECTURE arch OF cache IS
	TYPE CacheState IS (idle, memwrite_then_read, cwrite, memread, memwrite, check_addr_w, check_addr_r);
	SIGNAL state : CacheState;
	TYPE DirtyValid IS ARRAY(cache_size - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(0 TO 0);
	TYPE TagArr IS ARRAY(cache_size - 1 DOWNTO 0) OF STD_LOGIC_VECTOR (24 DOWNTO 0);

	SIGNAL dirty : DirtyValid; -- (dirty bit)
	SIGNAL valid : DirtyValid; -- (valid bit)
	SIGNAL tags : TagArr;
	TYPE CacheStructure IS ARRAY(cache_size - 1 DOWNTO 0) OF STD_LOGIC_VECTOR (127 DOWNTO 0);
	SIGNAL CacheBlock : CacheStructure;

	ALIAS block_offset IS s_addr(1 DOWNTO 0);
	-- shouldn't we define that below when starting our process?
	ALIAS set IS s_addr(6 DOWNTO 2); -- here defines the index of the block we're looking at
	ALIAS tag IS s_addr(31 DOWNTO 7); -- here identifies which bblock we have from memory

BEGIN

	-- only sensitive to these signals (triggers available to other processes)
	PROCESS (clock, reset, s_read, s_write, state, m_waitrequest)
		VARIABLE tmp_mem_addr : INTEGER := 0;
		VARIABLE block_offset_int : INTEGER := 0;
		VARIABLE mem_bytes_offset : INTEGER := 0;
		VARIABLE set_int : INTEGER := 0;
	BEGIN
		-- load the block offset as an integer from the block signal above (easier to access cache mem)
		block_offset_int := to_integer(unsigned(block_offset));
		set_int := to_integer(unsigned(set));

		--initalise cache and dirty/valid vector
		--IF (now < 1 ps) THEN
		--	FOR i IN 0 TO cache_size - 1 LOOP
		--		CacheBlock(i) <= STD_LOGIC_VECTOR(to_unsigned(i MOD 256, 128));
		--		dirty(i) <= "0";
		--		valid(i) <= "0";
		--	END LOOP;
		--END IF;

		-- if reset, re-init cache & bits
		IF (reset = '1') THEN
			state <= idle;
			-- iterate through cache blocks to reset
			--FOR i IN 0 TO cache_size - 1 LOOP
			--	CacheBlock(i) <= STD_LOGIC_VECTOR(to_unsigned(i MOD 256, 128));
			--	dirty(i) <= "0";
			--	valid(i) <= "0";
			--END LOOP;
		ELSIF rising_edge(clock) THEN

			CASE state IS
					-- starting in default state
				WHEN idle =>
					--REPORT "in idle";
					s_waitrequest <= '1'; -- something is happening signal it to cache operator?
					IF s_write = '1' THEN
						state <= check_addr_w;
					ELSIF s_read = '1' THEN
						state <= check_addr_r;
					ELSE
						state <= idle;
					END IF;

					-- verify if we have a valid address for reading from memory
				WHEN check_addr_r =>
					-- hit
					REPORT "read address";
					IF (valid(set_int) = "1") AND (tags(set_int) = tag) THEN
						-- start reading from cache and writing to the output read data vector
						-- each block stores 16 bytes of data, i.e. 4 words, we wish to access 1 word
						-- i.e. 4 bytes of data - and put it into our readdata signal
						-- block_offset_int goes from 0 to 3, accessing lower word is 31 downto 0
						-- accessing 4th word is 127 down to 96
						s_readdata <= CacheBlock(set_int)((32 * (block_offset_int + 1)) - 1 DOWNTO 32 * block_offset_int);
						-- done reading go back to idle state after returning data
						s_waitrequest <= '0';
						state <= idle;

						-- dirty
					ELSIF dirty(set_int) = "1" THEN
						-- write back to memory
						state <= memwrite_then_read;

						-- not dirty, but tag not valid, 
					ELSIF valid(set_int) = "0" THEN
						-- should read data from memory (and load it in cache)
						state <= memread;
					ELSE

						-- means there was a miss, but data is clean 
						-- should request data from memory and load it to cache
						state <= check_addr_r;
					END IF;
				WHEN memwrite_then_read =>
					IF m_waitrequest = '1' AND mem_bytes_offset <= 3 THEN
						-- define the 15 bits address to replace block in memory
						m_addr <= (to_integer(unsigned(s_addr(14 DOWNTO 0)))) + mem_bytes_offset;
						m_read <= '0';
						m_write <= '1';
						m_writedata <= CacheBlock(set_int)((32 * block_offset_int + 7 + mem_bytes_offset * 8) - 1 DOWNTO (32 * block_offset_int + mem_bytes_offset * 8));
						mem_bytes_offset := mem_bytes_offset + 1;
						state <= memwrite_then_read;
					ELSIF mem_bytes_offset > 3 THEN
						mem_bytes_offset := 0;
						state <= memread;
					ELSE
						m_write <= '0';
						state <= memwrite_then_read;
					END IF;

				WHEN memread =>
					-- memory ready to read more
					IF m_waitrequest = '1' THEN
						-- give memory an address to read from, using the lower 15 bits of the address
						m_addr <= (to_integer(unsigned(s_addr(14 DOWNTO 0)))) + mem_bytes_offset;
						m_read <= '1';
						m_write <= '0';
						state <= memread;
					ELSIF m_waitrequest = '0' AND mem_bytes_offset > 3 THEN
						-- have completed reading 1 word from memory
						s_readdata <= CacheBlock(set_int)((32 * (block_offset_int + 1)) - 1 DOWNTO 32 * block_offset_int);
						-- update tag in cache memory for the block
						tags(set_int) <= tag;
						-- update clean & dirty tags
						dirty(set_int) <= "0";
						valid(set_int) <= "1";

						-- done reading from memory & added retrieved data from memory to cache
						s_waitrequest <= '0';
						-- done reading & writing from memory
						m_write <= '0';
						m_read <= '0';
						mem_bytes_offset := 0;
						-- go back to idle state until next request
						state <= idle;
					ELSIF m_waitrequest = '0' AND mem_bytes_offset <= 3 THEN
						-- still reading the same word from memory
						-- retrieve 8 bits from memory (sending 1 byte at a time)
						-- and put them in cache usijng the mem_bytes_offset 
						-- reading the nth word in memory, 127 downto 96 for example
						-- first 127 downto 120, second 119 down to 112, third 111 down to 104
						-- fourth 103 down to 96
						-- get tmp address to find in cache block right byte
						tmp_mem_addr := (32 * block_offset_int) + 8 * mem_bytes_offset;
						CacheBlock(set_int)(tmp_mem_addr + 7 DOWNTO tmp_mem_addr) <= m_readdata;
						-- increment cache block offset
						mem_bytes_offset := mem_bytes_offset + 1;
						state <= memread;
					ELSE
						-- memory not ready to read more, wait until then
						state <= idle;
					END IF;

					--check if block valid and not dirty
				WHEN check_addr_w =>
					-- if either dirty or invalid and tags different, i.e. miss dirty
					IF (dirty(set_int) = "1") AND (valid(set_int) = "0" OR tags(set_int) /= tag) THEN
						state <= memwrite;
					ELSE
						-- reset the tags to reflect recent writing
						state <= cwrite;
					END IF;

				WHEN cwrite =>
					REPORT "writing data to cache";
					CacheBlock(set_int)((block_offset_int + 1) * 32 - 1 DOWNTO block_offset_int * 32) <= s_writedata;
					dirty(set_int) <= "1";
					valid(set_int) <= "1";
					tags(set_int) <= tag;
					s_waitrequest <= '0';
					state <= idle;

				WHEN memwrite =>
					IF m_waitrequest = '1' AND mem_bytes_offset <= 3 THEN
						m_addr <= (to_integer(unsigned(s_addr(14 DOWNTO 0)))) + mem_bytes_offset;
						m_read <= '0';
						m_write <= '1';
						m_writedata <= CacheBlock(set_int)((32 * block_offset_int + 7 + mem_bytes_offset * 8) - 1 DOWNTO (32 * block_offset_int + mem_bytes_offset * 8));
						mem_bytes_offset := mem_bytes_offset + 1;
						state <= memwrite;
					ELSIF mem_bytes_offset > 3 THEN
						CacheBlock(set_int)((block_offset_int + 1) * 32 - 1 DOWNTO block_offset_int * 32) <= s_writedata;
						tags(set_int) <= tag;
						mem_bytes_offset := 0;
						s_waitrequest <= '0';
						m_write <= '0';
						state <= idle;
					ELSE
						m_write <= '0';
						state <= memwrite;
					END IF;
			END CASE;

		END IF;
	END PROCESS;
END arch;