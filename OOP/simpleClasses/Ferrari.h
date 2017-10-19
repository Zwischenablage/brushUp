#include "Car.h"
class Ferrari : public Car
{
    public:
        Ferrari(int maxSpeed, int horsePower, int maxPassengers, std::string type);
        ~Ferrari();

        int getHorsePower();

        std::string getDescription(){ return m_make +  ", " + m_type; }
        int getNumSeats(){ return m_maxPassengers;}
        int getHP() { return m_horsePower;}
        int getMaxSpeed() { return m_maxSpeed;}

    private:
        int m_horsePower;
};

