import multiprocessing

bind = "127.0.0.1:8000"  # fronted by nginx (see webproxy-setup.sh) - no reason to expose this directly
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "sync"
timeout = 30
accesslog = "/opt/app/log/gunicorn-access.log"
errorlog = "/opt/app/log/gunicorn-error.log"
capture_output = True
