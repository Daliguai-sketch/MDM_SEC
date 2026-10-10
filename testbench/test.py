from src.sec_class_define import data_desc
from src.sec_class_define import golden_desc
from sec_core.sec_core_ctrl import run_sec_core
from testbench.load_tv import read_tv_files


def gen_input_data():


def testbench(tv_path):
    golden = golden_desc()
    golden = read_tv_files(tv_path)
    gen_input_data(golden.)


if __name__ == "__main__":

    tv_path = "C:\proj\sec\script\mdm_sec\\tv\cmd_d"
    testbench(tv_path)