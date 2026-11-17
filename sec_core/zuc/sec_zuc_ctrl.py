from ..zuc import sec_zuc_core
from typing import List
import math
from src.sec_class_define import data_desc


class zuc_ctrl_fsm:
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


    # in zuc, priv: int >= enc
    def fsm_process(self):
        if self.state == "IDLE":
            if self.sec_mode == 0 or self.sec_mode == 3: #enc
                if self.enc_start:
                    self.state = "INIT_ENC"
                elif self.int_start:
                    self.state = "INIT_INT"
            elif self.sec_mode == 1 or self.sec_mode == 2: #int
                if self.int_start:
                    self.state = "INIT_INT"
                elif self.enc_start:
                    self.state = "INIT_ENC"
        elif self.state == "INIT_ENC":
            #init 循环32轮
            for i in range(32):
                zt,self.enc_init_w,self.enc_s,self.enc_r = sec_zuc_core.zuc_core(init=1,w=self.enc_init_w,s=self.enc_s,r=self.enc_r)
            # 丢弃一轮 stream
            zt,self.enc_init_w,self.enc_s,self.enc_r = sec_zuc_core.zuc_core(init=0,w=self.enc_init_w,s=self.enc_s,r=self.enc_r)
            if self.enc_data_vld[self.enc_round]:
                self.state = "GEN_ENC_STREAM"
            else:
                self.state = "WAIT"
        elif self.state == "INIT_INT":
            #init 循环32轮, 丢弃一轮， 一共33
            for i in range(32):
                zt,self.int_init_w,self.int_s,self.int_r = sec_zuc_core.zuc_core(init=1,w=self.int_init_w,s=self.int_s,r=self.int_r)
            # 丢弃一轮 stream
            zt,self.int_init_w,self.int_s,self.int_r = sec_zuc_core.zuc_core(init=0,w=self.int_init_w,s=self.int_s,r=self.int_r)
            if self.int_data_vld[self.int_round] :
                self.state = "GEN_INT_STREAM"
            else:
                self.state = "WAIT"
        elif self.state == "GEN_ENC_STREAM":
            zt,self.enc_init_w,self.enc_s,self.enc_r = sec_zuc_core.zuc_core(init=0,w=self.enc_init_w,s=self.enc_s,r=self.enc_r)
            self.enc_stream_list.append(zt)
            self.enc_round += 1
            if (self.enc_round == self.enc_round_max):
                if ((self.sec_mode >= 2) and (self.int_round < self.int_round_max)):
                    self.state = "GEN_INT_STREAM" 
                else:
                    self.state = "DONE"
            # to init_int
            elif self.int_round == 0 and (self.sec_mode == 3): #only enc2int, gen_enc_stream -> init_int
                self.state = "INIT_INT"
            elif self.sec_mode >= 2 and self.int_round < self.int_round_max : 
            #elif self.sec_mode >= 2 and self.int_data_vld[self.int_round] : #int2enc, if int_vld, first int
                self.state = "GEN_INT_STREAM"
            elif self.enc_data_vld[self.enc_round]:
                self.state = "GEN_ENC_STREAM"       
            else:
                self.state = "WAIT"
        elif self.state == "GEN_INT_STREAM":
            zt,self.int_init_w,self.int_s,self.int_r = sec_zuc_core.zuc_core(init=0,w=self.int_init_w,s=self.int_s,r=self.int_r)
            self.int_stream_list.append(zt)
            self.int_round += 1
            if (self.int_round == self.int_round_max):
                if self.enc_round < self.enc_round_max:
                    self.state = "GEN_ENC_STREAM"
                else: 
                    self.state = "DONE"           
            # to init_int
            elif self.enc_round == 0 and (self.sec_mode == 2): #only int2enc, gen_int_stream -> init_enc
                self.state = "INIT_ENC"
            #elif self.sec_mode >= 2 and self.enc_data_vld[self.enc_round] : #enc2int, if enc_vld, first enc
            elif self.sec_mode >= 2 and self.enc_round < self.enc_round_max:
                self.state = "GEN_ENC_STREAM"
            elif self.int_data_vld[self.int_round]:
                self.state = "GEN_INT_STREAM"       
            else:
                self.state = "WAIT"           
        elif self.state == "WAIT":
            if self.int_data_vld[self.int_round]:
                self.state = "GEN_INT_STREAM"
            elif self.enc_data_vld[self.enc_round]:
                self.state = "GEN_ENC_STREAM"
        elif self.state == "DONE":
            self.state = "IDLE"
        
        return self.state

def gen_stream(zuc:zuc_ctrl_fsm,int_start,int_stream_num,int_data_vld:List,enc_start,enc_stream_num,enc_data_vld:List):
    zuc.start(int_start,enc_start,int_stream_num,enc_stream_num,int_data_vld,enc_data_vld)
    print("###############Print state turn##############")
    while(True):
        state = zuc.fsm_process()
        print(state)
        if state == "DONE":
            break
    
def fun_cipher(enc_stream:List,enc_data:data_desc,cipher_data:data_desc):
    enc_last_stream_bytes = enc_data.data_len % 4
    for i in range(len(enc_stream)):
        # last
        if enc_data.last[i]:
            if enc_last_stream_bytes == 1:
                enc_stream[i] &= 0xFF000000
            elif enc_last_stream_bytes == 2:
                enc_stream[i] &= 0xFFFF0000
            elif enc_last_stream_bytes == 3:
                enc_stream[i] &= 0xFFFFFF00
        cipher_data_tmp = enc_stream[i] ^ enc_data.data[i]
        cipher_data.data.append(cipher_data_tmp)
        cipher_data.data_vld.append(enc_data.data_vld[i])
        cipher_data.last.append(enc_data.last[i])
        cipher_data.data_len = enc_data.data_len

'''
def calc_mac(msg,z0,z1):
    T = 0
    z = []
    bits_width = 32
    bin_msg = bin(msg)[2:].zfill(bits_width)
    bin_msg_list = [int(bit) for bit in bin_msg]

    bin_z0 = bin(z0)[2:].zfill(bits_width)
    bin_z1 = bin(z1)[2:].zfill(bits_width)
    tmp_z_list = [int(bit) for bit in bin_z0]
    z.extend(tmp_z_list)
    tmp_z_list = [int(bit) for bit in bin_z1]
    z.extend(tmp_z_list)

    for i in range(32):
        z_int = int(''.join(map(str,z[i:i+32])),2)
        if bin_msg_list[i] == 1:
            T ^= z_int
    return T
'''
def get_word(int_stream, bit_index):
    """
    Extract 32 consecutive keystream bits
    starting at bit_index.

    MSB-first.
    """

    word_index = bit_index // 32
    bit_offset = bit_index % 32

    if bit_offset == 0:
        return int_stream[word_index] & 0xFFFFFFFF

    z0 = int_stream[word_index]
    z1 = int_stream[word_index + 1]

    return (
        ((z0 << bit_offset) & 0xFFFFFFFF)
        | (z1 >> (32 - bit_offset))
    ) & 0xFFFFFFFF

def fun_gen_mac(int_stream:List,int_data:data_desc,o_mac_data:data_desc):
    """
    ZUC 128-EIA3 MAC.

    Message length is measured in bytes.
    Message bit ordering is MSB-first.
    """

    msg_len = int_data.data_len
    bit_len = msg_len * 8

    required_words = math.ceil(bit_len / 32) + 2

    if len(int_stream) < required_words:
        raise ValueError(
            f"Insufficient keystream: "
            f"required={required_words}, "
            f"actual={len(int_stream)}"
        )

    # Convert 32-bit input words into message bytes.
    msg = bytearray()

    for word in int_data.data:
        msg.extend(
            (word & 0xFFFFFFFF).to_bytes(4, "big")
        )

    msg = msg[:msg_len]

    if len(msg) != msg_len:
        raise ValueError("Input message shorter than data_len")

    T = 0

    # Process actual message bits.
    for bit_index in range(bit_len):

        byte_index = bit_index // 8
        bit_in_byte = 7 - (bit_index % 8)

        if (msg[byte_index] >> bit_in_byte) & 1:

            T ^= get_word(
                int_stream,
                bit_index
            )

    # Final length-dependent keystream window.
    T ^= get_word(
        int_stream,
        bit_len
    )

    # Final keystream XOR.
    T ^= int_stream[math.ceil(bit_len / 32) + 1]

    mac = T & 0xFFFFFFFF

    o_mac_data.data.append(mac)
    o_mac_data.data_vld.append(1)
    o_mac_data.last.append(1)
    o_mac_data.data_len = 4

    return mac
    '''
    mac = 0
    L = math.ceil(int_data.data_len/4) + 2
    msg = []
    msg.extend(int_data.data)
    rem_bytes= int_data.data_len % 4
    sec_last_msg = msg.pop()
    # 在msg末尾填充 1bit 的1
    if rem_bytes == 0:
        # 对齐
        lst_msg = 1 << 31
    elif rem_bytes == 1:
        sec_last_msg = (sec_last_msg & 0xFF000000) | (1 << 23)
        lst_msg = 0
    elif rem_bytes == 2:
        sec_last_msg = (sec_last_msg & 0xFFFF0000) | (1 << 15)
        lst_msg = 0
    elif rem_bytes == 3:
        sec_last_msg = (sec_last_msg & 0xFFFFFF00) | (1 << 7)
        lst_msg = 0
    msg.append(sec_last_msg)
    msg.append(lst_msg)


    for i in range(L):
        if i == L-1:
            break
        z0 = int_stream[i]
        z1 = int_stream[i+1]
        mac ^= calc_mac(msg[i],z0,z1)

    lst_stream = int_stream[-1]
    mac ^= lst_stream
    o_mac_data.data.append(mac)
    o_mac_data.data_vld.append(1)
    o_mac_data.last.append(1)
    o_mac_data.data_len = 4
    '''

def run_zuc(
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
    enc_iv0 = enc_iv2 = (i_bearer << 27) | (i_direction << 26) | 0
    enc_iv1 = enc_iv3 = i_count
    fresh =  (i_bearer << 27) | 0
    int_iv0 = (fresh & 0xFFFF0000) | ((fresh & 0x00008000)^i_direction) | (fresh & 0x00007FFF)
    int_iv1 = ((i_count & 0x80000000) ^ i_direction) | (i_count & 0x7FFFFFFF)
    int_iv2 = fresh
    int_iv3 = i_count
    int_iv = [int_iv0 , int_iv1 , int_iv2 , int_iv3]
    enc_iv = [enc_iv0 , enc_iv1 , enc_iv2 , enc_iv3]
    int_start = i_start & (i_sec_mode != 0)
    enc_start = i_start & (i_sec_mode != 1)

    zuc = zuc_ctrl_fsm(i_sec_mode)
    sec_zuc_core.init_parameters(i_int_key,int_iv,zuc.int_s,zuc.int_r)
    sec_zuc_core.init_parameters(i_enc_key,enc_iv,zuc.enc_s,zuc.enc_r)

    enc_stream_num = math.ceil(enc_data.data_len/4)
    int_stream_num = math.ceil(int_data.data_len/4) + 2
    int_stream_vld = []
    for i in range(int_stream_num):
        int_stream_vld.append(1)

    gen_stream(zuc,int_start,int_stream_num,int_stream_vld,enc_start,enc_stream_num,enc_data.data_vld)
    
    #cipher
    if zuc.sec_mode != 1:
        fun_cipher(zuc.enc_stream_list,enc_data,o_cipher_data)
        print("print cipher \n")
        for i in range (len(o_cipher_data.data)):
            print(hex(o_cipher_data.data[i]))

    #mac
    if zuc.sec_mode != 0:
        fun_gen_mac(zuc.int_stream_list,int_data,o_mac_data)
        if o_mac_data.data:
            print("Print MAC")
            print(hex(o_mac_data.data[0]))
            print("print int stream \n")
            for i in range (len(zuc.int_stream_list)):
                print(hex(zuc.int_stream_list[i]))


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

    run_zuc(i_sec_mode,i_start,i_count,i_bearer,i_direction,i_int_key,i_enc_key,i_enc_data,i_int_data,o_cipher_data,o_mac_data)
        
    # 128 bit IV: 4 words