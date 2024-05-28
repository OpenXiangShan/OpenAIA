/* Copyright bosc
 * author: zhaohong
 * Function: recognize axi-lite msi,and map the setipnum*/

module imsic_axi_top #(
parameter AXI_ID_WIDTH          = 5,     // axi id width.
parameter AXI_ADDR_WIDTH        = 32,     // 15bit is valid when 7 interrupt files,and 1:1if max spec:16384*65 is needed, the least 33bit will be must.
parameter NR_INTP_FILES         = 7,      // m,s,5vs,
parameter NR_HARTS              = 1,      //64,      // the total harts number in each group.
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
input                                       axi_clk        ,
input                                       axi_rstn       , 
input                                       fifo_rstn      , //axi_rstn & sw_rstn. 
// bus to access the m interrupt file
input                                       m_awvalid_s    ,     
input       [AXI_ADDR_WIDTH-1:0]            m_awaddr_s     ,     
output wire [AXI_ID_WIDTH-1  :0]            m_bid_s        ,      
output wire [AXI_ID_WIDTH-1  :0]            m_rid_s        ,      
input       [AXI_ID_WIDTH-1  :0]            m_arid_s       ,      
input       [AXI_ID_WIDTH-1  :0]            m_awid_s       ,      
output wire                                 m_awready_s    ,      
input  wire                                 m_wvalid_s     ,      
output wire                                 m_wready_s     ,      
input  wire [31:0]                          m_wdata_s      ,
output wire                                 m_bvalid_s     ,      
input  wire                                 m_bready_s     ,      
output wire [1:0]                           m_bresp_s      ,
input                                       m_arvalid_s    ,      
input       [AXI_ADDR_WIDTH-1:0]            m_araddr_s     ,     
output wire                                 m_arready_s    ,      
output wire                                 m_rvalid_s     ,      
input                                       m_rready_s     ,      
output wire [31:0]                          m_rdata_s      ,     
output wire [1:0]                           m_rresp_s      ,
//bus to access the s interrupt file
input                                       s_awvalid_s    ,     
input       [AXI_ADDR_WIDTH-1:0]            s_awaddr_s     ,     
output wire [AXI_ID_WIDTH-1  :0]            s_bid_s        ,      
output wire [AXI_ID_WIDTH-1  :0]            s_rid_s        ,      
input       [AXI_ID_WIDTH-1  :0]            s_arid_s       ,      
input       [AXI_ID_WIDTH-1  :0]            s_awid_s       ,      
output wire                                 s_awready_s    ,      
input  wire                                 s_wvalid_s     ,      
output wire                                 s_wready_s     ,      
input  wire [31:0]                          s_wdata_s      ,
output wire                                 s_bvalid_s     ,      
input  wire                                 s_bready_s     ,      
output wire [1:0]                           s_bresp_s      ,
input                                       s_arvalid_s    ,      
input       [AXI_ADDR_WIDTH-1:0]            s_araddr_s     ,     
output wire                                 s_arready_s    ,      
output wire                                 s_rvalid_s     ,      
input                                       s_rready_s     ,      
output wire [31:0]                          s_rdata_s      ,     
output wire [1:0]                           s_rresp_s      ,
//imsic_csr_top
output wire [MSI_INFO_WIDTH-1:0]            o_msi_info     ,
output wire                                 o_msi_info_vld    // m,s,5vs,4harts.0-3:hart0-hart3 m file. 4-9:hart0 s+vs file.
);

wire                             fifo_wr          ;
wire                             addr_is_illegal  ;
wire                             m_reg_wr         ;
wire [31:0]                      m_reg_waddr      ;
wire [31:0]                      m_reg_wdata      ;
wire                             msi_m_idle       ;

wire                             s_reg_wr         ;
wire [31:0]                      s_reg_waddr      ;
wire [31:0]                      s_reg_wdata      ;
wire                             msi_s_idle       ;

imsic_axi2reg #(
    .IS_INTP_MFILE               (1             ),
    .AXI_ID_WIDTH                (AXI_ID_WIDTH  ),
    .AXI_ADDR_WIDTH              (AXI_ADDR_WIDTH)
)u_m_imsic_axi2reg(
    //input signal
    .clk                         (axi_clk                        ),
    .rstn                        (axi_rstn                       ),
    .bid_s                       (m_bid_s[AXI_ID_WIDTH-1: 0]     ),   
    .rid_s                       (m_rid_s[AXI_ID_WIDTH-1: 0]     ),   
    .arid_s                      (m_arid_s[AXI_ID_WIDTH-1:0]     ),     
    .awid_s                      (m_awid_s[AXI_ID_WIDTH-1:0]     ),     
    .awvalid_s                   (m_awvalid_s                    ),
    .awaddr_s                    (m_awaddr_s[AXI_ADDR_WIDTH-1:0] ),
    .wvalid_s                    (m_wvalid_s                     ),
    .wdata_s                     (m_wdata_s                      ),
    .bready_s                    (m_bready_s                     ),
    .bresp_s                     (m_bresp_s[1:0]                 ),
    .arvalid_s                   (m_arvalid_s                    ),
    .araddr_s                    (m_araddr_s[AXI_ADDR_WIDTH-1:0] ),
    .rvalid_s                    (m_rvalid_s                     ),
    .addr_is_illegal             (addr_is_illegal                ),
    .fifo_wr                     (fifo_wr                        ),
    .msi_recv_vld                (msi_s_idle                     ),
    .msi_idle                    (msi_m_idle                     ),
    .awready_s                   (m_awready_s                    ),
    .wready_s                    (m_wready_s                     ),
    .bvalid_s                    (m_bvalid_s                     ),
    .arready_s                   (m_arready_s                    ),
    .rready_s                    (m_rready_s                     ),
    .rdata_s                     (m_rdata_s[31:0]                ),
    .rresp_s                     (m_rresp_s[1:0]                 ),
    .reg_wr                      (m_reg_wr                       ),
    .reg_waddr                   (m_reg_waddr[AXI_ADDR_WIDTH-1:0]),
    .reg_wdata                   (m_reg_wdata[31:0]              )                             
);

imsic_axi2reg #(
    .IS_INTP_MFILE               (0             ),
    .AXI_ID_WIDTH                (AXI_ID_WIDTH  ),
    .AXI_ADDR_WIDTH              (AXI_ADDR_WIDTH)
)u_s_imsic_axi2reg(
    //input signal
    .clk                         (axi_clk                        ),
    .rstn                        (axi_rstn                       ),
    .bid_s                       (s_bid_s[AXI_ID_WIDTH-1: 0]     ),   
    .rid_s                       (s_rid_s[AXI_ID_WIDTH-1: 0]     ),   
    .arid_s                      (s_arid_s[AXI_ID_WIDTH-1:0]     ),     
    .awid_s                      (s_awid_s[AXI_ID_WIDTH-1:0]     ),     
    .awvalid_s                   (s_awvalid_s                    ),
    .awaddr_s                    (s_awaddr_s[AXI_ADDR_WIDTH-1:0] ),
    .wvalid_s                    (s_wvalid_s                     ),
    .wdata_s                     (s_wdata_s                      ),
    .bready_s                    (s_bready_s                     ),
    .bresp_s                     (s_bresp_s[1:0]                 ),
    .arvalid_s                   (s_arvalid_s                    ),
    .araddr_s                    (s_araddr_s[AXI_ADDR_WIDTH-1:0] ),
    .rvalid_s                    (s_rvalid_s                     ),
    .addr_is_illegal             (addr_is_illegal                ),
    .fifo_wr                     (fifo_wr                        ),
    .msi_recv_vld                (msi_m_idle                     ),
    .msi_idle                    (msi_s_idle                     ),
    .awready_s                   (s_awready_s                    ),
    .wready_s                    (s_wready_s                     ),
    .bvalid_s                    (s_bvalid_s                     ),
    .arready_s                   (s_arready_s                    ),
    .rready_s                    (s_rready_s                     ),
    .rdata_s                     (s_rdata_s[31:0]                ),
    .rresp_s                     (s_rresp_s[1:0]                 ),
    .reg_wr                      (s_reg_wr                       ),
    .reg_waddr                   (s_reg_waddr[AXI_ADDR_WIDTH-1:0]),
    .reg_wdata                   (s_reg_wdata[31:0]              )                             
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
    .clk                         (axi_clk                        ),
    .rstn                        (fifo_rstn                      ),//modify by zhaohong.2024.05.20
    .fifo_rstn                   (fifo_rstn                      ),
    .msi_s_busy                  ((~msi_s_idle)                  ),
    .m_reg_wr                    (m_reg_wr                       ),
    .m_reg_waddr                 (m_reg_waddr[AXI_ADDR_WIDTH-1:0]),
    .m_reg_wdata                 (m_reg_wdata[31:0]              ),                            
    .fifo_wr                     (fifo_wr                        ),
    .s_reg_wr                    (s_reg_wr                       ),
    .s_reg_waddr                 (s_reg_waddr[AXI_ADDR_WIDTH-1:0]),
    .s_reg_wdata                 (s_reg_wdata[31:0]              ),                            
    //output signal
    .addr_is_illegal             (addr_is_illegal                ),
    .o_msi_info_vld              (o_msi_info_vld                 ),
    .o_msi_info                  (o_msi_info[MSI_INFO_WIDTH-1:0])
);



endmodule
