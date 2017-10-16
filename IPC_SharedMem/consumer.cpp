#include "common.h"
#include <iostream>
#include <signal.h>
using namespace boost::interprocess;

volatile sig_atomic_t stop;

void inthand(int signum) { stop = 1; }

int main(int argc, char *argv[]) {
    while (!stop) {

        // Open the managed segment
        managed_shared_memory segment(open_only, "MySharedMemory");

        // Find the vector using the c-string name
        MyShmStringVector *myvector = segment.find<MyShmStringVector>("myshmvector").first;

        if (NULL != myvector) {

            // Use vector in reverse order
            std::sort(myvector->rbegin(), myvector->rend());

            std::cout << "Received: " << (*myvector)[0] << std::endl;

            // When done, destroy the vector from the segment
            segment.destroy<MyShmStringVector>("myshmvector");
        }

        sleep(1);
    }

    return 0;
}
