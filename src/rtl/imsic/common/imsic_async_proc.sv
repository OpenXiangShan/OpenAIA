module imsic_async_proc #(
parameter GEILEN            = 5,    // m,s,5vs,
parameter NR_INTP_FILES     = 2+GEILEN,    // m,s,5vs,
parameter NR_HARTS          = 1 ,   //harts number,modify from 64 to 1, in 20240528.
parameter NR_SRC            = 256,
parameter EID_VLD_DLY_NUM   = 0, // cycles that seteip_num_vld can be delayed before used. for timing.
// DO NOT INSTANCE BY PARAMETER
localparam NR_SRC_WIDTH      = $clog2(NR_SRC) , //max is 12.
localparam NR_HARTS_WIDTH    = (NR_HARTS ==1) ? 1 : $clog2(NR_HARTS),             //6
localparam INTP_FILE_WIDTH   = $clog2(NR_INTP_FILES), // 3
localparam MSI_INFO_WIDTH    = NR_HARTS_WIDTH + INTP_FILE_WIDTH + NR_SRC_WIDTH   //17bit
)
(
input                                       csr_clk	                                ,
input                                       csr_rstn	                            , 
input       [MSI_INFO_WIDTH-1:0]            i_msi_info                              ,
input                                       i_msi_info_vld	                        ,// m,s,5vs,4harts.0-3:hart0-hart3 m file. 4-9:hart0 s+vs file.
output reg  [MSI_INFO_WIDTH-1:0]            o_msi_info                              ,
output wire                                 o_msi_info_vld	                         // sync with csr_csr_clk
);
reg                                         msi_info_vld        ;
wire                                        msi_vld_sync        ;  
reg                                         msi_vld_sync_1dly   ;  
wire                                        msi_vld_sync_neg    ;  
reg                                         msi_vld_sync_neg_1dly; 
//=== start=======
//start:code about synchronize of setipnum_vld
cmip_dff_sync #(.N(3)) u_cmip_dff_sync
(.clk       (csr_clk             ),
 .rstn      (csr_rstn            ),
 .din       (i_msi_info_vld      ),
 .dout      (msi_vld_sync        )
);

always @(posedge csr_clk or negedge csr_rstn)
begin
    if (~csr_rstn) begin
        msi_vld_sync_1dly        <= 1'b0;
        msi_vld_sync_neg_1dly    <= 1'b0;
    end
    else begin
        msi_vld_sync_1dly        <= msi_vld_sync;
        msi_vld_sync_neg_1dly    <= msi_vld_sync_neg;
    end
end
assign msi_vld_sync_neg = msi_vld_sync_1dly & (~msi_vld_sync);
assign o_msi_info_vld   = msi_vld_sync_neg_1dly;
always @(posedge csr_clk or negedge csr_rstn)
begin
    if (~csr_rstn)
        o_msi_info[MSI_INFO_WIDTH-1:0] <= {MSI_INFO_WIDTH{1'b0}};
    else if (msi_vld_sync_neg)
        o_msi_info                     <= i_msi_info ;
end

endmodule
