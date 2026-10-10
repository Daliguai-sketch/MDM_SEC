from typing import List

class data_desc:
    def __init__(self,data:List[int],data_vld:List[int],last:List[int],data_len:int):
        self.data = data
        self.data_vld = data_vld
        self.last = last
        self.data_len = data_len
    
    def clear(self):
        self.data.clear()
        self.data_vld.clear()
        self.last.clear()
        self.data_len = 0

    def add_element(self,data,vld,last_flag):
        self.data.append(data)
        self.data_vld.append(vld)
        self.last.append(last_flag)

    def update_data_len(self,byte_len):
        self.data_len = byte_len


class golden_desc:
    def __init__(self):
        # para
        self.direction = 0
        self.rbtype = 0
        self.bearer = 0
        self.cmd = 0
        self.pdcp_sn_bit_size = 0
        self.sdap_hdr = 0
        self.is_sdap_hdr_exit = 0
        self.interrupt = 0
        self.pdcp_sn = 0
        self.counter = 0
        self.maci_out_byte_offset = 0
        self.maci_in_byte_offset = 0
        self.int_alg_id = 0
        self.enc_alg_id = 0
        self.cipher_out_byte_offset = 0
        self.cipher_in_byte_offset = 0
        self.int_out_byte_offset = 0
        self.int_in_byte_offset = 0

        #data
        self.packet_total_len = 0
        self.cipher_key = []
        self.int_key = []
        self.in_data = [] #二维数组[data_desc,data_desc]
        self.in_data_seg_num = 0
        self.in_data_seg_len = [] # 一维数组
        self.out_data = []

    def calc_len(self):
        total_len = 0
        for i in range(self.in_data_seg_num):
            total_len += self.in_data_seg_len[i]
            self.in_data[i].data_len = self.in_data_seg_len[i]
        self.packet_total_len = total_len


class cmd_desc_struct:
    def __init__(self):
        self.sec_mode = 0  #2bit 0:enc,1:int,2:int2enc,3:enc2int,4:null

        # use for sec_mode == 2/3
        self.mac_append = 0  # 0:mac在maci_out_byte_offset处， 1：mac在数据包
        self.mac_enc = 0  # 1：对mac加密/解密， 0：不对mac加密/解密
        self.mac_pt = 0 # 1:基于明文计算icv,  0:基于密文计算icv,

        # state conv， 7个原子操作
        self.hdr_en = 0 #hdr
        self.move_en = 0 # move
        #self.int_move_en = 0 # int & move & mac
        self.int_en = 0 # int & mac
        self.enc_en = 0 # enc
        #self.int2enc = 0 # pre_int & int & enc
        #self.enc2int = 0 # pre_int & int & enc
        # 源数据包分成4部分， --4--，---2---，-------1--------，--3--，
        # 其中：4：NAS时 mac位置， 3：AS时mac位置， 故3,4 不会并存， 
        #       1：proc_len, 加密或者move的数据，   2：pre_aad_len, 只做完
        self.pre_aad_len = 0 # pre add len
        self.pre_aad_in_byte_offset = 0
        self.proc_len = 0 # 16bit 
        self.proc_in_byte_offset = 0
        self.int_len = 0 # 16bit only use in int
        self.int_in_byte_offset = 0 # 16bit only use in int
        self.mac_len = 4 # 固定为4byte
        self.mac_out_en = 0 #加完保
        self.mac_out_byte_offset = 0
        self.mac_load_en = 0 #解完保
        self.mac_load_byte_offset = 0
        self.hdr_len = 0
        # 目的数据包
        # 按照 hdr+proc往外罗列；   
        # Out
        self.out_addr_start = 0