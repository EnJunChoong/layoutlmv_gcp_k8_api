import os
from typing import Dict, List, Any
from subprocess import run

from fastapi import FastAPI, File, UploadFile, HTTPException, status, Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from PIL import Image
from io import BytesIO
from jose import jwt, JWTError

from torch import device, cuda
from model import Model


WORK_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(WORK_DIR)

# set device
device = device("cuda" if cuda.is_available() else "cpu")

# Setup token authentication
SECRETKEY = os.environ["secretkey"]
PLAINTEXT = "PLAINTEXT" #dummy plaintext. Do not expose plaintext in prod. This is only for demo
ALGORITHM = "HS256" #Do not expose algorithm in prod. This is only for demo

token_auth_scheme = HTTPBearer()

app = FastAPI()
model_path = os.path.join(WORK_DIR, "models/philschmid/layoutlm-funsd")
model = Model(path=model_path, device=device)


def check_content_type(content_type: str, allowed_list=[]):
    """Require request MIME-type to be application/vnd.api+json"""

    if content_type not in allowed_list:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            f"Unsupported media type: {content_type}."
            f" It must be one of {allowed_list}",
        )


@app.get("/")
def read_root():
    return "Hello World"

@app.post("/inference_image/")
async def run_inference(token: str = Depends(token_auth_scheme), file: UploadFile=File(...)):
    
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token.credentials, SECRETKEY, algorithms=[ALGORITHM])
        plaintext = payload.get("key")
        if plaintext != PLAINTEXT:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    check_content_type(file.content_type, allowed_list=["image/jpeg", "image/png"])

    contents = await file.read()  
    
    image = Image.open(BytesIO(contents))
    image = image.convert("RGB")
    result = model.predict(image=image)
    return result