/* Copyright bosc
 * author: zhaohong
 * Function: recognize axi-lite msi,and map the setipnum*/

module imsic_axi_top #(
parameter AXI_ID_WIDTH          = 5,     // axi id width.
parameter AXI_ADDR_WIDTH        = 32,     //if max spec:16384*65 is needed, the least 33bit will be must.
parameter NR_INTP_FILES         = 7,      // m,s,5vs,
parameter NR_HARTS              = 64,      // the total harts number in each group.
parameter NR_SRC                = 256,     // msi src number,1~2047.
parameter SETIP_KEEP_CYCLES     = 8,
// DO NOT INSTANCE BY PARAMETER
localparam NR_SRC_WIDTH         = $clog2(NR_SRC),
localparam NR_HARTS_WIDTH       = (NR_HARTS ==1) ? 1 : $clog2(NR_HARTS),             //6
localparam INTP_FILE_WIDTH      = $clog2(NR_INTP_FILES), // 3
localparam MSI_INFO_WIDTH       = NR_HARTS_WIDTH + INTP_FILE_WIDTH + NR_SRC_WIDTH   //17bit
)
(
//  crg
input                                       axi_clk	       ,
input                                       axi_rstn	   , 
input                                       fifo_rstn      , //axi_rstn & sw_rstn. 
// bus                                                      
input                                       awvalid_s	   , 	
input       [AXI_ADDR_WIDTH-1:0]            awaddr_s	   , 	
output wire [AXI_ID_WIDTH-1  :0]            bid_s          , 	 
output wire [AXI_ID_WIDTH-1  :0]            rid_s          , 	 
input       [AXI_ID_WIDTH-1  :0]            arid_s         , 	 
input       [AXI_ID_WIDTH-1  :0]            awid_s         , 	 
output wire                                 awready_s	   , 	 
input  wire                                 wvalid_s	   , 	 
output wire                                 wready_s	   , 	 
input  wire [31:0]                          wdata_s	       ,
output wire                                 bvalid_s	   , 	 
input  wire                                 bready_s	   , 	 
output wire [1:0]                           bresp_s	       ,
input                                       arvalid_s	   , 	 
input       [AXI_ADDR_WIDTH-1:0]            araddr_s	   , 	
output wire                                 arready_s	   , 	 
output wire                                 rvalid_s	   , 	 
input                                       rready_s	   , 	 
output wire [31:0]                          rdata_s	       , 	
output wire [1:0]                           rresp_s	       ,
output wire [MSI_INFO_WIDTH-1:0]            o_msi_info     ,
output wire                                 o_msi_info_vld	// m,s,5vs,4harts.0-3:hart0-hart3 m file. 4-9:hart0 s+vs file.
);

wire                             fifo_wr        ;
wire                             addr_is_illegal;
wire                             reg_wr         ;
wire [31:0]                      reg_waddr      ;
wire [31:0]                      reg_wdata      ;

imsic_axi2reg #(
    .AXI_ID_WIDTH                (AXI_ID_WIDTH  ),
    .AXI_ADDR_WIDTH              (AXI_ADDR_WIDTH)
)u_imsic_axi2reg(
	//input signal
	.clk                         (axi_clk                      ),
	.rstn                        (axi_rstn                     ),
    .bid_s                       (bid_s[AXI_ID_WIDTH-1: 0]     ),   
    .rid_s                       (rid_s[AXI_ID_WIDTH-1: 0]     ),   
    .arid_s                      (arid_s[AXI_ID_WIDTH-1:0]     ),     
    .awid_s                      (awid_s[AXI_ID_WIDTH-1:0]     ),     
	.awvalid_s                   (awvalid_s                    ),
	.awaddr_s                    (awaddr_s[AXI_ADDR_WIDTH-1:0] ),
	.wvalid_s                    (wvalid_s                     ),
	.wdata_s                     (wdata_s                      ),
	.bready_s                    (bready_s                     ),
	.bresp_s                     (bresp_s[1:0]                 ),
	.arvalid_s                   (arvalid_s                    ),
	.araddr_s                    (araddr_s[AXI_ADDR_WIDTH-1:0] ),
	.rvalid_s                    (rvalid_s                     ),
	.addr_is_illegal             (addr_is_illegal              ),
	.fifo_wr                     (fifo_wr                      ),
	//output signal
	.awready_s                   (awready_s                    ),
	.wready_s                    (wready_s                     ),
	.bvalid_s                    (bvalid_s                     ),
	.arready_s                   (arready_s                    ),
	.rready_s                    (rready_s                     ),
	.rdata_s                     (rdata_s[31:0]                ),
	.rresp_s                     (rresp_s[1:0]                 ),
	.reg_wr                      (reg_wr                       ),
    .reg_waddr                   (reg_waddr[AXI_ADDR_WIDTH-1:0]),
    .reg_wdata                   (reg_wdata[31:0]              )                             
);

imsic_regmap #(
    .AXI_ADDR_WIDTH    (AXI_ADDR_WIDTH   ) ,
    .SETIP_KEEP_CYCLES (SETIP_KEEP_CYCLES) ,
    .NR_SRC_WIDTH      (NR_SRC_WIDTH     ) , 
    .NR_HARTS          (NR_HARTS         ) , 
    .NR_HARTS_WIDTH    (NR_HARTS_WIDTH   ) , 
    .FIFO_DATA_WIDTH   (MSI_INFO_WIDTH   ) , 
    .NR_INTP_FILES     (NR_INTP_FILES    ) ,
    .INTP_FILE_WIDTH   (INTP_FILE_WIDTH  ) 
) u_imsic_regmap(
	//input signal
	.clk                         (axi_clk                      ),
	.rstn                        (axi_rstn                     ),
	.fifo_rstn                   (fifo_rstn                    ),
	.reg_wr                      (reg_wr                       ),
    .reg_waddr                   (reg_waddr[AXI_ADDR_WIDTH-1:0]),
    .reg_wdata                   (reg_wdata[31:0]              ),                            
	.fifo_wr                     (fifo_wr                      ),
	//output signal
	.addr_is_illegal             (addr_is_illegal              ),
	.o_msi_info_vld              (o_msi_info_vld               ),
	.o_msi_info                  (o_msi_info[MSI_INFO_WIDTH-1:0])
);



endmodule
