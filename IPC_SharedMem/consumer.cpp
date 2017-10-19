#include "common.h"
#include <iostream>
#include <signal.h>
#include <chrono>
#include <thread>

using namespace boost::interprocess;

volatile sig_atomic_t stop;

void inthand(int signum) { stop = 1; }

int main(int argc, char *argv[]) {
    while (!stop) {

        // Open the managed segment
        managed_shared_memory segment(open_only, "MySharedMemory");

        // Find the vector using the c-string name
		std::pair<MyShmString*, std::size_t> p = segment.find<MyShmString>("SharedMemString");
        if (p.first) {
            std::cout << "Received: " << (*p.first) << std::endl;

            // When done, destroy the vector from the segment
            segment.destroy<MyShmString>("SharedMemString");
        }

	    std::this_thread::sleep_for(std::chrono::milliseconds(500));
		
    }

    shared_memory_object::remove("MySharedMemory");



    return 0;
}
