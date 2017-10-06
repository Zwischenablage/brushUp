#include "glut.h"
#include <algorithm>
#include <chrono> // std::chrono::seconds
#include <ctime>
#include <iomanip>
#include <iostream>
#include <math.h>
#include <random> // std::default_random_engine
#include <thread> // std::this_thread::sleep_for
#include <vector>

using namespace std;

#define KEY_ESCAPE 27
#define NUM_CITIES 7
float travelRecord;
bool firstRun;

vector<pair<float, float> > salesMan;
vector<pair<float, float> > shortestRoute;

typedef struct {
  int width;
  int height;
  char *title;

  float field_of_view_angle;
  float z_near;
  float z_far;
} glutWindow;

glutWindow win;

float getDistance(vector<pair<float, float> > currentTravel) {
  float thisDistance = 0.0f;
  for (int i = 0; i < currentTravel.size(); ++i) {
    thisDistance +=
        sqrt(pow(currentTravel[i].first - currentTravel[i + 1].first, 2.0) +
             pow(currentTravel[i].second - currentTravel[i + 1].second, 2.0));
  }
  cout << "Distance is " << thisDistance << endl;
  return thisDistance;
}

float getRand() {
  float result = static_cast<float>(rand()) / static_cast<float>(RAND_MAX);
  int neg = rand() % 11;

  if (neg > 5) {
    result *= -1.0f;
  }
  return result;
}

// random generator function:
int myrandom(int i) { return std::rand() % i; }

void drawCities() {
  glClear(GL_COLOR_BUFFER_BIT |
          GL_DEPTH_BUFFER_BIT); // Clear Screen and Depth Buffer
  glLoadIdentity();
  glTranslatef(0.0f, 0.0f, -3.0f);

  glEnable(GL_VERTEX_PROGRAM_POINT_SIZE);
  glPointSize(10);
  glBegin(GL_POINTS);

  // DRAW original cities
  vector<std::pair<float, float> >::iterator it;
  glColor3f(0.0f, 0.0f, 1.0f);

  for (int i = 0; i < salesMan.size(); ++i) {
    glVertex2f(salesMan[i].first, salesMan[i].second);
  }
  glEnd();

  // randomize cities
  vector<pair<float, float> > currentTravel = salesMan;
  random_shuffle(currentTravel.begin(), currentTravel.end(), myrandom);
  float tmpDistance = getDistance(currentTravel);
  cout << "Update - travelRecord: " << travelRecord << endl;
  if (tmpDistance < travelRecord) {
    cout << "FOUND SHORTER ROUTE!!!" << endl;
    travelRecord = tmpDistance;
    shortestRoute = currentTravel;
  }
  
  
  if (!firstRun) 
  {

  glLineWidth(1);
  glBegin(GL_LINE_STRIP);
  glColor3f(255.0f, 255.0f, 255.0f);
  for (int i = 0; i < currentTravel.size(); ++i) {
    glVertex2f(currentTravel[i].first, currentTravel[i].second);
  }
  glEnd();

  glLineWidth(4);
  glBegin(GL_LINE_STRIP);
  glColor3f(255.0f, 0.0f, 0.0f);
  for (int i = 0; i < shortestRoute.size(); ++i) {
    glVertex2f(shortestRoute[i].first, shortestRoute[i].second);
  }
  glEnd();
}


  glutSwapBuffers();
  
  if (firstRun) {
    std::this_thread::sleep_for(std::chrono::seconds(5));
    firstRun = false;
  }

  // std::this_thread::sleep_for(std::chrono::milliseconds(100));
}

void initialize() {
  glMatrixMode(GL_PROJECTION);             // select projection matrix
  glViewport(0, 0, win.width, win.height); // set the viewport
  glMatrixMode(GL_PROJECTION);             // set matrix mode
  glLoadIdentity();                        // reset projection matrix
  GLfloat aspect = (GLfloat)win.width / win.height;
  gluPerspective(win.field_of_view_angle, aspect, win.z_near,
                 win.z_far);  // set up a perspective projection matrix
  glMatrixMode(GL_MODELVIEW); // specify which matrix is the current matrix
  glShadeModel(GL_SMOOTH);
  glClearDepth(1.0f); // specify the clear value for the depth buffer
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_LEQUAL);
  glHint(GL_PERSPECTIVE_CORRECTION_HINT,
         GL_NICEST); // specify implementation-specific hints
  glClearColor(0.0, 0.0, 0.0,
               1.0); // specify clear values for the color buffers
}

void keyboard(unsigned char key, int mousePositionX, int mousePositionY) {
  switch (key) {
  case KEY_ESCAPE:
    exit(0);
    break;

  default:
    break;
  }
}

char title[] = "Traveling Salesman";
int initGlut(int *argc, char **argv) {
  // set window values
  win.width = 800;
  win.height = 600;
  win.title = title;
  win.field_of_view_angle = 45;
  win.z_near = 1.0f;
  win.z_far = 5.0f;

  // initialize and run program
  glutInit(argc, argv); // GLUT initialization
  glutInitDisplayMode(GLUT_RGB | GLUT_DOUBLE | GLUT_DEPTH); // Display Mode
  glutInitWindowSize(win.width, win.height);                // set window size
  glutCreateWindow(win.title);                              // create Window
  glutDisplayFunc(drawCities); // register Display Function
  glutIdleFunc(drawCities);    // register Idle Function
  glutKeyboardFunc(keyboard);  // register Keyboard Handler
  initialize();
  glutMainLoop(); // run GLUT mainloop

  return 0;
}

int main(int argc, char *argv[]) {

  std::srand(std::time(0)); // needed once per program run

  for (int i = 0; i < NUM_CITIES; ++i) {
    float x, y;
    x = getRand();
    y = getRand();
    cout << "Adding: " << x << "," << y << endl;
    salesMan.push_back(make_pair(x, y));
  }

  travelRecord = getDistance(salesMan);
  shortestRoute = salesMan;
  firstRun = true;

  cout << setprecision(3) << "initial travelRecord = " << travelRecord << endl;

  initGlut(&argc, argv);

  return 0;
}