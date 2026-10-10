# detribute aes,snow3g,zuc
from .snow3g.sec_snow3g_ctrl import run_snow3g
from src.sec_class_define import data_desc
from .zuc.sec_zuc_ctrl import run_zuc
from .aes.sec_aes_ctrl import run_aes

def run_sec_core(
        i_sec_mode, #0:enc,1:int,2:int2enc,3:enc2int
        i_start,
        i_int_alg_id,
        i_enc_alg_id,
        i_count,
        i_bearer,
        i_direction,
        i_int_key,
        i_enc_key,
        # width 32
        i_enc_data:data_desc,
        i_int_data:data_desc,
        o_cipher_data:data_desc,
        o_mac_data:data_desc
        ):
    int_alg_null = 0
    enc_alg_null = 0
    snow_3g_start = 0
    aes_start = 0
    zuc_start = 0
    snow_3g_mode = 0
    aes_mode = 0
    zuc_mode = 0

    if i_sec_mode == 0: #enc
        match i_enc_alg_id:
            case 0:
                enc_alg_null = 1
            case 1:
                snow_3g_start = i_start
                snow_3g_mode = i_sec_mode
            case 2:
                aes_start = i_start
                aes_mode = i_sec_mode
            case 3:
                zuc_start = i_start
                zuc_mode = i_sec_mode
    elif i_sec_mode == 1: #int
        match i_int_alg_id:
            case 0:
                enc_alg_null = 1
            case 1:
                snow_3g_start = i_start
                snow_3g_mode = i_sec_mode
            case 2:
                aes_start = i_start
                aes_mode = i_sec_mode
            case 3:
                zuc_start = i_start
                zuc_mode = i_sec_mode
    elif i_sec_mode >= 2: #int2enc
        if i_int_alg_id == i_enc_alg_id:
            match i_int_alg_id:
                case 0:
                    enc_alg_null = 1
                case 1:
                    snow_3g_start = i_start
                    snow_3g_mode = i_sec_mode
                case 2:
                    aes_start = i_start
                    aes_mode = i_sec_mode
                case 3:
                    zuc_start = i_start
                    zuc_mode = i_sec_mode
        else:
            match i_int_alg_id:
                case 0:
                    enc_alg_null = 1
                case 1:
                    snow_3g_start = i_start
                    snow_3g_mode = 1 #int
                case 2:
                    aes_start = i_start
                    aes_mode = 1
                case 3:
                    zuc_start = i_start
                    zuc_mode = 1
            match i_enc_alg_id:
                case 0:
                    enc_alg_null = 1
                case 1:
                    snow_3g_start = i_start
                    snow_3g_mode = 0 #enc
                case 2:
                    aes_start = i_start
                    aes_mode = 0
                case 3:
                    zuc_start = i_start
                    zuc_mode = 0

    if enc_alg_null == 1:
        o_cipher_data = i_enc_data
    if int_alg_null == 1:
        o_mac_data.data = [0]
        o_mac_data.data_vld = [0]
        o_mac_data.last = [1]
        o_mac_data.data_len = 0

    # start snow3g
    run_snow3g(snow_3g_mode,snow_3g_start,i_count,i_bearer,i_direction,i_int_key,i_enc_key,i_enc_data,i_int_data,o_cipher_data,o_mac_data)

    # start aes
    run_aes(aes_mode,aes_start,i_count,i_bearer,i_direction,i_int_key,i_enc_key,i_enc_data,i_int_data,o_cipher_data,o_mac_data)

    # start zuc
    run_zuc(zuc_mode,zuc_start,i_count,i_bearer,i_direction,i_int_key,i_enc_key,i_enc_data,i_int_data,o_cipher_data,o_mac_data)


if __name__ == "__main__":
    a = 0
    # input
    i_int_start = 1
    i_enc_start = 1
    i_int_alg_id = 0 #0:null, 1:snow_3g, 2:aes, 3:zuc
    i_enc_alg_id = 0 #0:null, 1:snow_3g, 2:aes, 3:zuc

    i_sec_mode = 3 #0:enc,1:int,2:int2enc,3:enc2int
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
    #o_snow3g_enc_busy = int(0,1)
    o_cipher_data = []
    o_cipher_data_vld = []
    o_cipher_last = []
    i_int_data = [0x06070809,0x0a0b0cf6]
    i_int_data_vld = [1,1]
    i_int_last = [0,1]
    i_int_len = 8
    #o_snow3g_int_busy = int(0,1)
    o_mac_data = []
    o_mac_data_vld = []
    o_snow3g_done = 0

    run_snow3g(i_sec_mode,i_int_start,i_enc_start,i_count,i_bearer,i_direction,i_int_key,i_enc_key,i_enc_data,i_int_data,o_cipher_data,o_mac_data)