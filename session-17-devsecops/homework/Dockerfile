FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# SECURITY FIX: run as an unprivileged user instead of root
RUN useradd --create-home --uid 10001 appuser
USER appuser

EXPOSE 5001
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5001/health')"

# SECURITY FIX: production WSGI server instead of the Flask dev server (no debugger)
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "2", "--chdir", "app", "app:app"]
