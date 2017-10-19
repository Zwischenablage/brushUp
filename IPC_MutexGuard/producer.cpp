#include "common.h"
#include <iostream>
#include <chrono>
#include <thread>


boost::condition_variable cond;
boost::mutex mut;
bool data_ready;


void wait_for_data_to_process()
{
    boost::unique_lock<boost::mutex> lock(mut);
    while(!data_ready)
    {
        cond.wait(lock);
    }
    //process_data();
}


void prepare_data_for_processing()
{
    //retrieve_data();
    //prepare_data();
    {
        boost::lock_guard<boost::mutex> lock(mut);
        data_ready=true;
    }
    cond.notify_one();
}


void wait(int seconds)
{
    boost::this_thread::sleep_for(boost::chrono::seconds(seconds));
}

boost::mutex mutex;

void thread()
{
    using boost::this_thread::get_id;
    for (int i = 0; i < 5; ++i)
    {
        //    wait(1);

        boost::lock_guard<boost::mutex> lock(mutex);

        std::cout << "Thread " << get_id() << ": " << i << std::endl;
    }
}

int main()
{
    boost::thread t1(thread);
    boost::thread t2(thread);

    t1.join();
    std::cout << "Joined Thread1" << std::endl;
    t2.join();
    std::cout << "Joined Thread2" << std::endl;
}

