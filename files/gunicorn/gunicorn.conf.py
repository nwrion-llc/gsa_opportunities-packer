import multiprocessing

bind = "0.0.0.0:8000"
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
timeout = 30
accesslog = "/opt/app/log/gunicorn-access.log"
errorlog = "/opt/app/log/gunicorn-error.log"
capture_output = True
