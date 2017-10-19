EXECUTABLE=ferrari
CC=g++
SRC=$(wildcard *.cpp)


all: $(SRC)
	$(CC) -o $(EXECUTABLE) $^ $(CFLAGS)

	
clean:
	echo "cleaing up...."
	rm -rf *.o $(EXECUTABLE) 
