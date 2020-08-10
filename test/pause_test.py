import pause
from datetime import datetime, timedelta

print(datetime.now())
pause.until(datetime.now() + timedelta(seconds = 0.2))
print(datetime.now())

