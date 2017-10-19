#include "common.h"
#include <iostream>
#include <chrono>
#include <thread>




int main (int argc, char *argv[])
{
    managed_shared_memory managed_shm(open_or_create, "shm", 1024);
    int *i = managed_shm.find_or_construct<int>("Integer")();

    named_mutex named_mtx(open_or_create, "mtx");
    named_mtx.lock();
    ++(*i);
    std::cout << *i << '\n';
    std::this_thread::sleep_for(std::chrono::milliseconds(5000));
    named_mtx.unlock();


    return 0;
}
