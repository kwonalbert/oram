	
	// TODO hash digest size should be factored into the header size

	// Suffix meanings:
	// 	RawBits = what it sounds like ...
	// 	RndBits = bits rounded to some value (usually a DDR3 burst)
	// 	DRBursts = in terms of DDR3 bursts
	// 	DRWords = in terms of DDR3 DQ bus width (typically 64b)

	`ifdef SIMULATION
	localparam				IVINITValue =			{32'hdeadbeef, {AESEntropy-32{1'b0}}}; 	// Encryption initialization vector init values (1'bx makes it a bit cheaper in HW)
	
	initial begin
		if (ORAMB == PINIT || 
			ORAMU == PINIT ||
			ORAML == PINIT ||
			ORAMZ == PINIT ||
			BEDWidth == PINIT) begin
			$display("[%m] ERROR: parameter uninitialized.");
			$finish;
		end
	end
	`else
	localparam				IVINITValue =			{AESEntropy{1'bx}};
	`endif

	//--------------------------------------------------------------------------
	//	Raw bit fields
	//--------------------------------------------------------------------------	
	
	// Header flit
	localparam				BigVWidth =				ORAMZ,
							BigUWidth =				ORAMU * ORAMZ,
							BigLWidth =				ORAML * ORAMZ;
	localparam				BktHSize_ValidBits =	`divceil(ORAMZ, 8) * 8, // = 8 bits for Z < 9
							BktHWaste_ValidBits =	BktHSize_ValidBits - ORAMZ,
							BktHVStart =			AESEntropy,
							BktHUStart =			BktHVStart + BktHSize_ValidBits, // at what position do the U's start?
							BktHLStart =			BktHUStart + BigUWidth, // at what position do the U's start?
							BktHSize_RawBits = 		BktHLStart + BigLWidth; // valid bits, addresses, leaf labels; TODO change to be in terms of BktHLStart

	//--------------------------------------------------------------------------
	//	Quantities in terms of the Memory/DRAM width
	//--------------------------------------------------------------------------

	// Now, we align bitfields to DDR3 burst lengths.  This means (for BEDWidth 
	// == DDRDWidth) that we won't need expensive re-alignment logic in ORAM.  
	// For the BEDWidth < DDRDWidth case, we will lose bandwidth if ORAMB % 
	// DDRDWidth != 0.

	localparam				BlkSize_DRBursts =		`divceil(ORAMB, DDRDWidth),
							BktHSize_DRBursts = 	`divceil(BktHSize_RawBits, DDRDWidth),
							BktPSize_DRBursts =		ORAMZ * BlkSize_DRBursts,
							BktHSize_RndBits =		BktHSize_DRBursts * DDRDWidth, // = 512 for all configs we care about
							BktPSize_RndBits =		BktPSize_DRBursts * DDRDWidth;	
							
	localparam				BktSize_DRBursts =		BktHSize_DRBursts + BktPSize_DRBursts,
							BktSize_RndBits =		BktSize_DRBursts * DDRDWidth,
							BktSize_DRWords =		BktSize_RndBits / DDRDQWidth; // = E.g., for Z = 5, BktSize_TotalRnd = 3072 and BktSize_DDRWords = 48

	// ... and associated helper params
	localparam				
							PathSize_DRBursts =		(ORAML + 1) * BktSize_DRBursts,
							PathPSize_DRBursts =	(ORAML + 1) * BktPSize_DRBursts,
							BBSTWidth =				`log2(BktSize_DRBursts), // Block DRAM burst width
							PBSTWidth =				`log2(PathSize_DRBursts); // Path DRAM burst width		
	
	//--------------------------------------------------------------------------
	//	Quantities in terms of BEDWidth
	//--------------------------------------------------------------------------

	// BEDWidth/FEDWidth-related quantities
	localparam				BlkSize_BEDChunks =		BlkSize_DRBursts * `divceil(DDRDWidth, BEDWidth),
							BktHSize_BEDChunks =	`divceil(BktHSize_RndBits, BEDWidth),
							BktPSize_BEDChunks =	`divceil(BktPSize_RndBits, BEDWidth),
							BktSize_BEDChunks =		BktHSize_BEDChunks + BktPSize_BEDChunks,
							PathPSize_BEDChunks =	(ORAML + 1) * BktPSize_BEDChunks,
							PathSize_BEDChunks =	(ORAML + 1) * BktSize_BEDChunks;

	localparam				RHWidth =				BktHSize_BEDChunks * BEDWidth;
	