from src.sec_class_define import cmd_desc_struct

def cmd_decoder(i_cmd,i_packet_len,i_hdr_len,i_maci_out_byte_offset,i_maci_in_byte_offset,i_cipher_in_byte_offset,i_cipher_out_byte_offset,i_int_in_byte_offset):
    o_cmd_out = cmd_desc_struct()
    o_cmd_out.mac_len = 4
    o_cmd_out.out_addr_start = i_cipher_out_byte_offset
    # 纠正
    if i_int_in_byte_offset > i_cipher_in_byte_offset:
        int_in_byte_offset = i_cipher_in_byte_offset
    else:
        int_in_byte_offset = i_int_in_byte_offset

    o_cmd_out.pre_aad_len = i_cipher_in_byte_offset - int_in_byte_offset
    o_cmd_out.pre_aad_in_byte_offset = int_in_byte_offset
    o_cmd_out.proc_len = i_packet_len - i_cipher_in_byte_offset
    o_cmd_out.proc_in_byte_offset = i_cipher_in_byte_offset

    o_cmd_out.hdr_len = i_hdr_len
    match (i_cmd):
        case 0 : #move
            #In : ---invalid_in---,-----proc-----
            #Out: ---invalid_out---,-----proc-----
            o_cmd_out.move_en = 1
            o_cmd_out.sec_mode = 4
        case 1 : #head
            #In : 
            #Out: ---invalid_out---,--head--
            o_cmd_out.hdr_en = 1
            o_cmd_out.sec_mode = 4
        case 2 : # head & move
            #In : ---invalid---,-----proc-----,
            #Out: ---invalid_out---,--head--,-----proc-----,
            o_cmd_out.hdr_en = 1
            o_cmd_out.move_en = 1
            o_cmd_out.sec_mode = 4
        case 3 : #int
            #In : ---invalid---,---pre_aad----,-----proc-----
            #Out: ---invalid_out---,--mac--,
            o_cmd_out.int_en = 1
            o_cmd_out.mac_out_en =1
            o_cmd_out.mac_out_byte_offset = i_maci_out_byte_offset
            o_cmd_out.sec_mode = 1
        case 10 : #head & int
            #In : ---invalid---,---pre_aad----,-----proc-----,
            #Out: ---invalid_out---,--head--,--invalid--,--mac--
            o_cmd_out.hdr_en = 1
            o_cmd_out.int_en = 1
            o_cmd_out.mac_out_en = 1
            o_cmd_out.mac_out_byte_offset = i_maci_out_byte_offset
            o_cmd_out.sec_mode = 1
        case 11 : #as head & int & move
            #In : ---invalid---,---pre_aad----,-----proc-----,
            #Out: ---invalid---,---head----,-----proc-----,---mac_back---,
            o_cmd_out.hdr_en = 1
            o_cmd_out.int_en = 1
            o_cmd_out.move_en = 1
            o_cmd_out.mac_out_en = 1
            o_cmd_out.mac_out_byte_offset = o_cmd_out.proc_len + o_cmd_out.hdr_len
            o_cmd_out.sec_mode = 1
        case 5 : # as deint
            #In : ---invalid---,---pre_aad----,-----proc-----,---mac_back---,
            #Out: --no--
            o_cmd_out.int_en = 1
            # 纠偏
            o_cmd_out.pre_aad_len = o_cmd_out.pre_aad_len - o_cmd_out.mac_len
            o_cmd_out.mac_load_en = 1
            o_cmd_out.mac_load_byte_offset = i_packet_len - o_cmd_out.o_mac_len
            o_cmd_out.sec_mode = 1
        case 6 : # as deint & move, 
            #In : ---invalid---,---pre_aad----,-----proc-----,---mac_back---,
            #Out: ---invalid---,-----proc-----,---mac_back---,  特殊的， mac_back又会写到Out中
            o_cmd_out.int_en = 1 
            o_cmd_out.move_en = 1
            o_cmd_out.proc_len = o_cmd_out.proc_len - o_cmd_out.o_mac_len
            o_cmd_out.mac_load_en = 1
            o_cmd_out.mac_load_byte_offset = i_packet_len - o_cmd_out.o_mac_len
            o_cmd_out.mac_out_en = 1
            o_cmd_out.mac_out_byte_offset = o_cmd_out.proc_len + o_cmd_out.o_mac_len
            o_cmd_out.sec_mode = 1
        case 7 : # nas deint
            #In : ---invalid---,---mac_front---,---pre_aad----,-----proc-----,
            #Out: --no--
            o_cmd_out.int_en = 1
            o_cmd_out.mac_load_en = 1
            o_cmd_out.mac_load_byte_offset = i_maci_in_byte_offset
            o_cmd_out.sec_mode = 1
        case 4 : #enc
            #In : ---invalid---,-----proc-----,
            #Out: ---invalid---,-----proc-----,
            o_cmd_out.enc_en = 1
            o_cmd_out.sec_mode = 0
        case 8 : #dec
            #In : ---invalid---,-----proc-----,
            #Out: ---invalid---,-----proc-----,
            o_cmd_out.enc_en = 1
            o_cmd_out.sec_mode = 0
        case 12 : # head & enc
            #In : ---invalid---,-----proc-----,
            #Out: ---invalid---,--head--,-----proc-----,
            o_cmd_out.hdr_en = 1
            o_cmd_out.enc_en = 1
            o_cmd_out.sec_mode = 0
        case 13 : # nas上行 enc & int
            #In : ---invalid---,---pre_aad----,-----proc-----,
            #   : ---invalid---,---pre_aad----,-----cipher-----,
            #Out: ---invalid---,---mac_front---,---pre_aad----,-----cipher-----,
            # 特殊的： 加密完送去做完保
            o_cmd_out.enc_en = 1
            o_cmd_out.int_en = 1
            o_cmd_out.mac_pt = 0  # 基于密文计算mac
            o_cmd_out.mac_append = 0 # mac在数据包中间
            o_cmd_out.mac_enc = 0 # mac不加密
            o_cmd_out.mac_out_en = 1
            o_cmd_out.mac_out_byte_offset = i_maci_out_byte_offset
            o_cmd_out.sec_mode = 3
        case 14 : # as上行 head & int & enc
            #In : ---invalid---,---pre_aad----,-----proc-----,
            #Int: --head--,---pre_aad----,-----proc-----,
            #Enc: -----proc-----,--mac_back--,
            #Out: ---invalid---,--head--,-----cipher-----,--cipher--,
            # 特殊的： 计算出mac送去加密
            o_cmd_out.int_en = 1
            o_cmd_out.enc_en = 1
            o_cmd_out.hdr_en = 1
            o_cmd_out.mac_pt = 1  # 基于明文计算mac
            o_cmd_out.mac_append = 1 # mac在数据包结尾
            o_cmd_out.sec_mode = 2
            o_cmd_out.mac_enc = 0
        case 15 : # as 下行 dec & deint
            #In : ---invalid---,---pre_aad----,-----proc-----
            # ---invalid---,---pre_aad----,-----plaint-----,---plaint_mac_back---
            #Out: ---invalid---,-----plaint-----,---plaint_mac_back---
            # 特殊的： mac从enc解密结果中提取
            o_cmd_out.int_en = 1
            o_cmd_out.enc_en = 1
            o_cmd_out.mac_pt = 1  # 基于明文计算mac
            o_cmd_out.mac_append = 1 # mac在数据包结尾
            o_cmd_out.mac_enc = 1 # mac加密
            o_cmd_out.mac_load_en = 1 # mac从enc解密结果中提取 
            o_cmd_out.sec_mode = 3
        case 16 : # nas下行 deint & dec
            #In : ---invalid---,---mac_front---,---pre_aad----,-----proc-----,
            #Out: ---invalid---,-----plaint-----,
            o_cmd_out.int_en = 1
            o_cmd_out.enc_en = 1
            o_cmd_out.mac_pt = 0  # 基于密文计算mac
            o_cmd_out.mac_append = 0 # mac在数据包中间
            o_cmd_out.mac_enc = 0 # mac不加密
            o_cmd_out.mac_load_en = 1
            o_cmd_out.mac_load_byte_offset = i_maci_in_byte_offset
            o_cmd_out.sec_mode = 2
    return o_cmd_out
            
if __name__ == "__main__":
    #input
    i_cmd = 0 #5bit
    i_packet_len = 0 #16bit  from dma
    i_hdr_len = 0 #4bit,  from head 
    i_maci_out_byte_offset = 0
    i_maci_in_byte_offset = 0
    i_cipher_out_byte_offset = 0
    i_cipher_in_byte_offset = 0
    i_int_out_byte_offset = 0
    i_int_in_byte_offset = 0

    #addr
    #i_packet_src_addr = 0 #32bit
    #i_packet_dst_addr = 0 #32bit

    #out
    o_sec_mode = 0  #2bit 0:enc,1:int,2:int2enc,3:enc2int,4:null
    o_mac_append = 0  # 0:mac在maci_out_byte_offset处， 1：mac在数据包尾
    o_direc = 0 # 1: 上行加密， 0：下行解密
    o_mac_enc = 0  # 1：对mac加密/解密， 0：不对mac加密/解密
    o_mac_pt = 0 # 1:基于明文计算icv,  0:基于密文计算icv,
    
    # state conv， 7个原子操作
    o_hdr_en = 0 #hdr
    o_move_en = 0 # move
    o_int_move_en = 0 # int & move & mac
    o_int_en = 0 # int & mac
    o_enc_en = 0 # enc
    o_int2enc = 0 # pre_int & int & enc
    o_enc2int = 0 # pre_int & int & enc

    # 源数据包分成4部分， --4--，---2---，-------1--------，--3--，
    # ---invalid---,---nas mac---,---pre_aad----,-----proc-----,---as_mac---,
    # 其中：4：NAS时 mac位置， 3：AS时mac位置， 故3,4 不会并存， 
    #       1：proc_len, 加密或者move的数据，   2：pre_aad_len, 只做完保的数据， 实际上做完保hdr+pre_aad_len+proc_len
    o_pre_aad_len = 0 # pre add len
    o_pre_aad_in_byte_offset = 0
    o_proc_len = 0 # 16bit 
    o_proc_in_byte_offset = 0
    o_int_len = 0 # 16bit only use in int
    o_int_in_byte_offset = 0 # 16bit only use in int
    o_mac_len = 4 # 固定为4byte
    o_mac_in_byte_offset = 0
    o_mac_out_byte_offset = 0
    o_hdr_len = 0

    # 目的数据包
    # 按照 hdr+proc往外罗列；
    # mac是例外 ： as时 mac在最后， 其他： 输出在macoutoffset处
    
    #  move：原子操作长度，源相对于包起始的偏移， 目的相对于包输出地址的偏移
    o_move_len = 0 # 16bit
    o_move_src_in_byte_offset = 0 # 16bit
    o_move_dst_out_byte_offset = 0 # 16bit

    # head：原子操作长度，源地址，目的地址
    o_hdr_len = 0 # 16bit
    o_hdr_src_in_byte_offset = 0 # 16bit
    o_hdr_dst_out_byte_offset = 0 # 16bit

    #int
    o_int_len = 0 # 16bit
    o_int_src_in_byte_offset = 0 # 16bit
    #o_int_dst_out_byte_offset = 0 # 16bit

    o_maco_len = 0 #4bit, mac长度固定为4
    o_maco_dst_out_byte_offset = 0 # 16bit
    o_maci_len = 0 #4bit, mac长度固定为4
    o_maci_src_in_byte_offset = 0 # 16bit
    
    # first ： 看上行还是下行， 上行加密，完整性计算； 下行解密，完整性校验