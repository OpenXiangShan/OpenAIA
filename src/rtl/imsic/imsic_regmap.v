/* Copyright bosc
 * author: zhaohong
 * Function: reg access to map the setipnum*/

module imsic_regmap #(
//parameter BASE_ADDR_IMSIC       = 32'h24000000,//the addr support 16384 harts.
parameter AXI_ADDR_WIDTH     = 32, // m,s,5vs,4harts.0-3:hart0-hart3 m file. 4-9:hart0 s+vs file.
parameter SETIP_KEEP_CYCLES  = 8,
parameter NR_SRC_WIDTH       = 5,
parameter NR_HARTS_WIDTH     = 6,
parameter INTP_FILE_WIDTH    = 3,
parameter NR_HARTS           = 64,
parameter FIFO_DATA_WIDTH    = 17,
parameter NR_INTP_FILES      = 7 //>2
)
(
//  crg
input                                   clk	                            ,
input                                   rstn	                        , 
input                                   fifo_rstn                       , 
// imsic_axi2reg
output wire                             fifo_wr                         ,
output reg                              addr_is_illegal                 ,
input                                   reg_wr                          ,
input       [AXI_ADDR_WIDTH-1:0]        reg_waddr                       ,
input       [31:0]                      reg_wdata                       ,
output reg  [FIFO_DATA_WIDTH-1:0]       o_msi_info                      ,
output wire                             o_msi_info_vld		
);
localparam  SINTP_FILE_WIDTH            = $clog2(NR_INTP_FILES-1); // 3,number of  s files.
localparam  SFILE_ADDR_WIDTH            = 12+ SINTP_FILE_WIDTH + $clog2(NR_HARTS); //21
localparam  FIFO_DEPTH_WIDTH            = 3  ; // 2^FIFO_DEPTH_WIDTH,not more than (SETIP_KEEP_CYCLES+3)/2.

reg         [3:0]                       setip_cnt                       ;
reg                                     fifo_rdata_vld                  ;
wire                                    fifo_rd_tmp1                    ;
reg                                     fifo_rd_tmp                     ;
reg                                     fifo_rd_tmp_dly                 ;
wire                                    fifo_full                       ;
wire                                    fifo_empty                      ;
reg         [FIFO_DATA_WIDTH-1:0]       fifo_wdata                      ;
wire        [FIFO_DATA_WIDTH-1:0]       fifo_rdata                      ;
wire                                    setip_en_neg                    ;
reg                                     setip_cnt_en                    ;
reg                                     setip_cnt_en_dly                ;
reg                                     fifo_wr_wait                    ;
wire                                    fifo_rd                         ;
wire                                    fifo_wr_c1                      ;
wire                                    fifo_wr_c2                      ;

// ================================================================ 
//  // ========================= code:instance fifo ===============
generic_fifo_dc_gray #(
.dw (FIFO_DATA_WIDTH),
.aw (FIFO_DEPTH_WIDTH)
)   u_fifo(
.din        (fifo_wdata[FIFO_DATA_WIDTH-1:0]), 
.clk        (clk                            ),
.rst        (fifo_rstn                      ),
.we         (fifo_wr                        ),
.re         (fifo_rd                        ),
.dout       (fifo_rdata[FIFO_DATA_WIDTH-1:0]),
.full       (fifo_full                      ),
.empty      (fifo_empty                     )
);


// ================================================================ 
//  // ========================= code: fifo write/read control ====
assign fifo_wr_c1       = reg_wr & (~fifo_full);
assign fifo_wr_c2       = fifo_wr_wait & (~fifo_full);
assign fifo_wr          = (fifo_wr_c1 | fifo_wr_c2) & (~addr_is_illegal);

always @(posedge clk or negedge rstn)
begin
    if (~rstn) 
        fifo_wr_wait <= 1'b0;
    else if (reg_wr & fifo_full)
        fifo_wr_wait <= 1'b1;
    else if (~fifo_full)
        fifo_wr_wait <= 1'b0;
    else;
end
always @(*)
begin
        if (~fifo_wr)
            fifo_wdata = {FIFO_DATA_WIDTH{1'b0}};
        else begin
            fifo_wdata[NR_SRC_WIDTH-1:0] = reg_wdata[NR_SRC_WIDTH-1:0];
         // fifo_wdata[(NR_SRC_WIDTH + INTP_FILE_WIDTH -1):NR_SRC_WIDTH] = reg_waddr[SFILE_ADDR_WIDTH] ? 
            fifo_wdata[(NR_SRC_WIDTH + INTP_FILE_WIDTH -1):NR_SRC_WIDTH] = reg_waddr[21] ? 
                                         (reg_waddr[(SINTP_FILE_WIDTH+11):12] + {{(SINTP_FILE_WIDTH-1){1'b0}},1'b1}) : {INTP_FILE_WIDTH{1'b0}}; //m : index is 0. s and vs are 1~
            fifo_wdata[(FIFO_DATA_WIDTH-1):(FIFO_DATA_WIDTH-NR_HARTS_WIDTH)] = (NR_HARTS == 1'b1) ? 1'b0 : (reg_waddr[21] ? 
                                         (reg_waddr[(SFILE_ADDR_WIDTH-1) : (SFILE_ADDR_WIDTH -NR_HARTS_WIDTH)]) : reg_waddr[(NR_HARTS_WIDTH+11):12]);
        end
end
assign fifo_rd_tmp1     =  ~fifo_empty;
assign fifo_rd          = fifo_rd_tmp & (~fifo_rd_tmp_dly);
always @(posedge clk or negedge rstn)
begin
    if (~rstn) begin   
        setip_cnt_en_dly <= 1'b0;
        fifo_rd_tmp_dly  <= 1'b0;
    end
    else begin
        setip_cnt_en_dly <= setip_cnt_en;
        fifo_rd_tmp_dly  <= fifo_rd_tmp;
    end
end
assign setip_en_neg = setip_cnt_en_dly & (~setip_cnt_en);
always @(posedge clk or negedge rstn)
begin
    if (~rstn)    
        fifo_rd_tmp  <= 1'b0;
    else if (setip_en_neg)
        fifo_rd_tmp  <= 1'b0;
    else if (fifo_rd_tmp1)
        fifo_rd_tmp  <= 1'b1;
    else;
end
//code about gen setipnum
always @(*)
begin
        if (|reg_waddr[11:0]) // only 0x0,is illegal inside 4KB. 0x4 not supported.
            addr_is_illegal = 1'b1; 
     // else if (reg_waddr[SFILE_ADDR_WIDTH])begin // s file bit[21]=1,it is sfile addr space.
        else if (reg_waddr[21])begin // s file bit[21]=1,it is sfile addr space.
            if (reg_waddr[11+SINTP_FILE_WIDTH:12] > NR_INTP_FILES -2) // 14:12. 0~(7-2) is valid
                addr_is_illegal = 1'b1;
            else
                addr_is_illegal = 1'b0;
        end
        else if (|reg_waddr[(SFILE_ADDR_WIDTH-1):(12+$clog2(NR_HARTS))]) // bit[21]=0,it is mfile addr space. hartnum-- 20:18,assume nr_harts is 2^x
                addr_is_illegal = 1'b1;
        else
                addr_is_illegal = 1'b0;
end
//expand the setipnum_we , leave enough time to asynchronize before used in imsic_csr_top. 
always @(posedge clk or negedge rstn)
begin
    if (~rstn)
        fifo_rdata_vld <= 1'b0;
    else if (fifo_rd)
        fifo_rdata_vld <= 1'b1;
    else
        fifo_rdata_vld <= 1'b0;
end
always @(posedge clk or negedge rstn)
begin
    if (~rstn)
        o_msi_info[FIFO_DATA_WIDTH-1:0]   <= {FIFO_DATA_WIDTH{1'b0}};
    else if (fifo_rdata_vld) // assume all the interrupt files is allocated in sucession besides 4KB allignment. it is that Sfiles is the next 4KBs,followed after M files.
        o_msi_info[FIFO_DATA_WIDTH-1:0] <= fifo_rdata[FIFO_DATA_WIDTH-1:0]; 
    else;
end

always @(posedge clk or negedge rstn)
begin
    if (~rstn)
        setip_cnt[3:0]  <=  4'd0;
    else if (setip_cnt_en)
        setip_cnt[3:0]  <= setip_cnt[3:0] + 4'd1 ;
    else 
        setip_cnt[3:0]  <=  4'd0;
end
always @(posedge clk or negedge rstn)
begin
    if (~rstn)    
        setip_cnt_en  <= 1'b0;
    else if (fifo_rdata_vld)
        setip_cnt_en  <= 1'b1;
    else if(setip_cnt[3:0] >= SETIP_KEEP_CYCLES-1)
        setip_cnt_en <= 1'b0;
    else;
end
assign o_msi_info_vld = setip_cnt_en;

endmodule
