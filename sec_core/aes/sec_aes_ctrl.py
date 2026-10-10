from ..aes import sec_aes_core_int
from ..aes import sec_aes_core_enc
from typing import List
import math
from src.sec_class_define import data_desc
import math


class aes_ctrl_fsm:
    def __init__(self,sec_mode):
        self.state = "IDLE"
        self.enc_s : List[int] = [0] * 16
        self.enc_r : List[int] = [0] * 3
        self.enc_init_w = 0
        self.int_s : List[int] = [0] * 16
        self.int_r : List[int] = [0] * 3
        self.int_init_w = 0
        self.sec_mode = sec_mode  #0:enc,1:int,2:int2enc,3:enc2int
        self.int_stream_list = []
        self.enc_stream_list = []
        self.int_round = 0 # 生成stream计数
        self.enc_round = 0
        self.int_round_max = 0
        self.enc_round_max = 0
        #条件转换
        self.int_start = 0
        self.enc_start = 0
        #int_init_done
        #enc_init_done
        #int_data_vld
        #enc_data_vld
        #int_stream_done
        #enc_stream_done
        #int enc 生成stream的优先级看 sec_mode

    def start(self,int_start,enc_start,int_data_stream_num,enc_data_stream_num,int_data_vld,enc_data_vld):
        self.int_start = int_start
        self.enc_start = enc_start
        self.int_round_max = int_data_stream_num
        self.enc_round_max = enc_data_stream_num
        self.int_data_vld = int_data_vld
        self.enc_data_vld = enc_data_vld


    # in aes, has enc core and int core

# 128bits split 32*4
def split_128block(stream):
    stream_32 = []
    stream_32.append((stream >> 96) & 0xFFFFFFFF)
    stream_32.append((stream >> 64) & 0xFFFFFFFF)
    stream_32.append((stream >> 32) & 0xFFFFFFFF)
    stream_32.append(stream & 0xFFFFFFFF)
    return stream_32

def comb_128block(stream):
    block_128 = 0
    for i in range(4):
        block_128 |= (stream[i] << ((4-i-1) * 32))
    return block_128

def xor_128block(w1,w2):
    for i in range(4):
        w1[i] ^= w2[i]
    return w1
    
def fun_cipher(enc_iv,enc_key,enc_data:data_desc,cipher_data:data_desc):
    stream_cnt_max = math.ceil(enc_data.data_len / 16)
    stream_cnt = 0
    stream_list = []
    w = sec_aes_core_enc.aes_enc_key_exp(enc_key)

    # gen_stream
    for i in range(stream_cnt_max):
        stream = sec_aes_core_enc.aes_enc_core(enc_iv,w)
        # counter
        lst_iv = enc_iv.pop()
        lst_iv = (i + 1) & 0x1FFF
        enc_iv.append(lst_iv)
        stream_list.extend(stream)

    word_len = math.ceil(enc_data.data_len / 4)
    enc_last_stream_bytes = enc_data.data_len % 4
    for i in range(word_len):
        if i == word_len-1 :
            if enc_last_stream_bytes == 1:
                stream_list[i] &= 0xFF000000
            elif enc_last_stream_bytes == 2:
                stream_list[i] &= 0xFFFF0000
            elif enc_last_stream_bytes == 3:
                stream_list[i] &= 0xFFFFFF00
        cipher_data_tmp = stream_list[i] ^ enc_data.data[i]
        cipher_data.data.append(cipher_data_tmp)
        cipher_data.data_vld.append(enc_data.data_vld[i])
        cipher_data.last.append(enc_data.last[i])
        cipher_data.data_len = enc_data.data_len

def fun_gen_mac(int_iv,int_key,int_data:data_desc,o_mac_data:data_desc):
    mac = 0
    int_stream = []
    # calc K1, K2
    K1=0
    K2 = 0
    c = 0x87
    w = sec_aes_core_int.aes_int_key_exp(int_key)
    L = comb_128block(sec_aes_core_int.aes_int_core([0,0,0,0],w))
    msb_l = (L >> 127) & 1
    if msb_l:
        K1 = c ^ ((L << 1) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    else:
        K1 = (L << 1) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    msb_k1 = (K1 >> 127) & 1
    if msb_k1:
        K2 = c ^ ((K1 << 1) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
    else:
        K2 = (K1 << 1) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF

    msg_len = math.ceil((int_data.data_len+2*4)/16) # 包括了增加的2个word
    msg_rem = (int_data.data_len+2*4)%16
    msg = int_data.data.copy()
    aes_core_ret = [0,0,0,0]
    for i in range(msg_len):
        m = []
        if i==0 and i == msg_len -1: # fst & lst
            m.extend(int_iv)
            fill_word_num = math.ceil((msg_rem - 8) / 4)
            fill_byte_num = (msg_rem - 8) % 4
            for j in range(fill_word_num):
                tmp_m = msg.pop(0)
                if j == fill_word_num-1:
                    match(fill_byte_num):
                        case 1:
                            tmp_m = (tmp_m & 0xFF000000) | (1 << 23)
                        case 2:
                            tmp_m = (tmp_m & 0xFFFF0000) | (1 << 15)
                        case 3:
                            tmp_m = (tmp_m & 0xFFFFFF00) | (1 << 7)
                        case 0:
                            tmp_m = 1 << 31
                m.append(tmp_m)
        elif i == 0: #first
            m.extend(int_iv)
            for j in range(min(msg_len,2)):
                m.append(msg.pop(0))
        elif i == msg_len -1 and msg_rem: #last
            word_len = math.floor(msg_rem / 4)
            byte_rem = msg_rem % 4
            for j in range(word_len):
                m.append(msg.pop(0))
            if byte_rem:
                tmp_m = msg.pop(0)
                match(byte_rem):
                    case 1:
                        tmp_m = (tmp_m & 0xFF000000) | (1 << 23)
                    case 2:
                        tmp_m = (tmp_m & 0xFFFF0000) | (1 << 15)
                    case 3:
                        tmp_m = (tmp_m & 0xFFFFFF00) | (1 << 7)
                    case 0:
                        tmp_m = 1 << 31
                m.append(tmp_m)
            else:
                m.append(1 << 31)
        else:
            for j in range(4):
                m.append(msg.pop(0))
        for j in range(4-len(m)):
            # 填充m
            m.append(0)

        if i == 32:
            debug = 0
        state_in = []
        if i == msg_len - 1:
            if msg_rem :
                stream_k2 = split_128block(K2)
                a = xor_128block(stream_k2,aes_core_ret)
                state_in = xor_128block(m,a)
                #state_in = xor_128block(xor_128block(stream_k2,m),aes_core_ret)
            else:
                stream_k1 = split_128block(K1)
                state_in = xor_128block(xor_128block(stream_k1,m),aes_core_ret)
        else:
            state_in = xor_128block(m,aes_core_ret)
        state_out = sec_aes_core_int.aes_int_core(state_in,w)
        int_stream.append(state_out)
        aes_core_ret = state_out

    mac = aes_core_ret[0]
    

    o_mac_data.data.append(mac)
    o_mac_data.data_vld.append(1)
    o_mac_data.last.append(1)
    o_mac_data.data_len = 4
    return int_stream

def run_aes(
        i_sec_mode,
        i_start,
        i_count,
        i_bearer,
        i_direction,
        i_int_key,
        i_enc_key,
        enc_data:data_desc,
        int_data:data_desc,
        o_cipher_data:data_desc,
        o_mac_data:data_desc
        # width 32
        #i_enc_data,
        #i_enc_data_vld,
        #i_enc_last,
        #i_enc_len,
        #i_int_data,
        #i_int_data_vld,
        #i_int_last,
        #i_int_len
        ):
    if i_start == 0:
        return
    #parameter init
    stream_cnt = 0
    enc_iv0 = i_count
    enc_iv1 = (i_bearer << 27) | (i_direction << 26) | 0
    enc_iv2 = 0
    enc_iv3 = stream_cnt & 0x1FFF
    enc_iv = [enc_iv0 , enc_iv1 , enc_iv2 , enc_iv3]
    int_iv = [enc_iv0 , enc_iv1]

    int_start = i_start & (i_sec_mode != 0)
    enc_start = i_start & (i_sec_mode != 1)

    #mac
    if int_start:
        # int_iv 64bits
        int_stream = fun_gen_mac(int_iv,i_int_key,int_data,o_mac_data)
        #if o_mac_data.data:
        #    print("Print AES MAC")
        #    print(hex(o_mac_data.data[0]))
        #    print("print int stream \n")
            #for i in range (len(int_stream)):
            #    # 128block
            #    for j in range(4):
            #        print(hex(int_stream[i][j]))

    #cipher, 状态矩阵是IV
    if enc_start :
        fun_cipher(enc_iv,i_enc_key,enc_data,o_cipher_data)
        #print("print AES cipher \n")
        #for i in range (len(o_cipher_data.data)):
        #    print(hex(o_cipher_data.data[i]))


if __name__ == "__main__":
    # input
    i_sec_mode = 3 #0:enc,1:int,2:int2enc,3:enc2int
    i_start = 1
    i_count = 0x36af6144
    i_bearer = 0x1f
    i_direction = 0x0
    i_int_key = [0xf1722635, 0x58da3019, 0x44a74cf3, 0x83fd23a2]
    i_enc_key = [0x4881ff48, 0x952c4910, 0x82c5b300, 0xabd6459f]
    
    # width 32
    i_enc_data = [0x0d0e0f10,0x11121314,0x15161718,0x191a1b1c,0x1d1e1f20,0x21222324,0x25262728,0x292a2b2c]
    i_enc_data_vld = [1,1,1,1,1,1,1,1]
    i_enc_last     = [0,0,0,0,0,0,0,1]
    i_enc_len = 32

    o_cipher_data = []
    o_cipher_data_vld = []
    o_cipher_last = []

    i_int_data = [0x06070809,0x0a0b0cf6]
    i_int_data_vld = [1,1]
    i_int_last = [0,1]
    i_int_len = 8

    o_mac_data = []
    o_mac_data_vld = []
    o_zuc_done = 0
    i_enc_data = data_desc(i_enc_data,i_enc_data_vld,i_enc_last,i_enc_len)
    i_int_data = data_desc(i_int_data,i_int_data_vld,i_int_last,i_int_len)
    o_mac_data = data_desc()
    o_cipher_data = data_desc()
        
    # 128 bit IV: 4 words