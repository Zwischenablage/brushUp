#include "common.h"
#include <signal.h>
#include <sstream>
#include <iostream>


volatile sig_atomic_t stop;

void inthand(int signum) {
    stop = 1;
}

int main (int argc, char *argv[])
{
    if (argc != 2) 
    {
        std::cout << "argc : " << argc << " Wrong number of arguments" << std::endl;
        return -1;
    }
    //Obtain handle value
    std::string message = argv[1]; 
    std::cout << "Sending string " << message << std::endl;

    //shared_memory_object::remove("MySharedMemory");
    managed_shared_memory shm(open_or_create , "MySharedMemory", 10000);
		
	MyShmString *s = shm.find_or_construct<MyShmString>("SharedMemString")(message.c_str(), shm.get_segment_manager());

    return 0;
}
