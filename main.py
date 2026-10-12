from sense_hat import SenseHat
from time import sleep
import os
import json

s = SenseHat()

def getTemp():
    raw = s.get_temperature()
    cpu = float(os.popen("vcgencmd measure_temp").read()[5:-3])
    temp = raw - (cpu - raw) / 5.466
    temp = round(temp, 1)
    return temp
    
def getHumidity():
    return round(s.get_humidity(), 1)

def getPressure():
    return round(s.get_pressure(), 1)

def jsonWrite(temp, humidity, pressure):
    data = {
        "temperature": temp,
        "humidity": humidity,
        "air-pressure": pressure}
    
    with open("data.tmp", "w") as f:
        json.dump(data, f)
    os.replace("data.tmp", "data.json")    
    

if __name__ == "__main__":
    
    while True:
        jsonData = jsonWrite(getTemp(), getHumidity(), getPressure())
        
        sleep(5)
    
    