import os, mimetypes
from PIL import Image
from locust import HttpUser, between, task

print("enter token")
secret_key=input()

class test_inference_image(HttpUser):
    wait_time = between(3,5)
    
    def on_start(self):
        self.headers={"Authorization": f"Bearer {secret_key}"}       

        path_to_image="test_72.png"
        with open(path_to_image, "rb") as f:
            self.bytes_obj = f.read()
            self.fname = os.path.basename(path_to_image)
            self.content_type = mimetypes.guess_type(path_to_image)[0]
    
    @task
    def inference_image(self):
        self.client.post("/inference_image/", headers=self.headers, files={"file": ( self.fname, self.bytes_obj, self.content_type)})
    # @task
    # def docs(self):
    #     self.client.get("/docs")