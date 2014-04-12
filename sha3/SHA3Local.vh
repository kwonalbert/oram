
	localparam  FullDigestWidth = 512;
	
	localparam  TrancateDigestWidth = `min(BktHSize_RndBits - BktHSize_RawBits, FullDigestWidth);
	
	localparam	DigestStart = FullDigestWidth,
				DigestEnd = FullDigestWidth - TrancateDigestWidth;
				
	localparam PathBufAWidth = `log2(2 * PathSize_DRBursts + 2 * BktSize_DRBursts + BktHSize_DRBursts * (ORAML+1));