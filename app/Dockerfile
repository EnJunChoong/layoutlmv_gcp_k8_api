# Using python 3.7.3
FROM google/cloud-sdk:394.0.0-slim
ENV K_SERVICE layoutlmv2_api

# Allow statements and log messages to immediately appear in the logs
ENV PYTHONUNBUFFERED True

# system install here
RUN apt-get update && apt-get install -y curl libgl1 tesseract-ocr libtesseract-dev

# Prep apps folder and make it work DIR
RUN mkdir /app
WORKDIR "/app"

# Install python library
COPY ./requirements.txt /app/requirements.txt
RUN pip3 install --upgrade pip
RUN pip3 install -r requirements.txt
# RUN python -m pip install 'git+https://github.com/facebookresearch/detectron2.git'

# COPY the rest after all installation
COPY ./models /app/models
COPY ./*.py /app/

EXPOSE 80
ENTRYPOINT ["uvicorn", "main:app", "--port", "80", "--host", "0.0.0.0"]