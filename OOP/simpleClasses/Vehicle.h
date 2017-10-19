#include <string>

class Vehicle
{

    protected:
        int m_maxSpeed;
        int m_numWheels;
        int m_maxPassengers;

        std::string m_make;
        std::string m_type;

        Vehicle(int maxSpeed, int wheels, int maxPassengers, std::string make, std::string type) 
            : m_maxSpeed(maxSpeed), m_numWheels(wheels), m_maxPassengers(maxPassengers)
              ,m_make(make), m_type(type) {}
        ~Vehicle(){}

        virtual int getMaxSpeed() = 0;
        virtual int getNumWheels() = 0;
        virtual int getMaxPessengers() = 0;

        virtual std::string getMake() = 0;
        virtual std::string getType() = 0;


};
