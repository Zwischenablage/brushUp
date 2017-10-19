#include "Vehicle.h"

class Car: public Vehicle
{
    protected:
        Car(int maxSpeed, int maxPassengers, std::string make, std::string type);
        ~Car();

        int getMaxSpeed();
        int getNumWheels();
        int getMaxPessengers();

        std::string getMake();
        std::string getType();
};
