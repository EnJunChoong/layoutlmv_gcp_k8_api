import os
from typing import Dict, List, Any
from PIL import Image

from transformers import LayoutLMForTokenClassification, LayoutLMv2Processor
# from transformer import LayoutLMForTokenClassification, LayoutLMv3Processor
# from transformers import AutoProcessor, AutoModelForTokenClassification
import torch

os.environ["TOKENIZERS_PARALLELISM"] = "false"
# helper function to unnormalize bboxes for drawing onto the image
def unnormalize_box(bbox, width, height):
    return [
        width * (bbox[0] / 1000),
        height * (bbox[1] / 1000),
        width * (bbox[2] / 1000),
        height * (bbox[3] / 1000),
    ]


class Model:
    def __init__(self, path:str, device):
        # load model and processor from path
        self.device = device
        self.processor = LayoutLMv2Processor.from_pretrained(path)
        self.model = LayoutLMForTokenClassification.from_pretrained(path).to(self.device)

        
        self.processor.save_pretrained("/mnt/d/layoutlmv_gcp_k8_api/models/philschmid/layoutlm-funsd")
        self.model.save_pretrained("/mnt/d/layoutlmv_gcp_k8_api/models/philschmid/layoutlm-funsd")

    def predict(self, image: Image) -> Dict[str, List[Any]]:
        """
        Args:
            image: accept PIL.Image as input
        """
        # process image
        encoding = self.processor(image, return_tensors="pt").to(self.device)
        
        # run prediction
        with torch.inference_mode():
            outputs = self.model(
                input_ids=encoding.input_ids.to(self.device),
                bbox=encoding.bbox.to(self.device),
                attention_mask=encoding.attention_mask.to(self.device),
                token_type_ids=encoding.token_type_ids.to(self.device),
            )
            predictions = outputs.logits.softmax(-1)

        # post process output
        result = []
        for item, inp_ids, bbox in zip(
            predictions.squeeze(0).cpu(), encoding.input_ids.squeeze(0).cpu(), encoding.bbox.squeeze(0).cpu()
        ):
            label = self.model.config.id2label[int(item.argmax().cpu())]
            if label == "O":
                continue
            score = item.max().item()
            text = self.processor.tokenizer.decode(inp_ids)
            bbox = unnormalize_box(bbox.tolist(), image.width, image.height)
            result.append({"label": label, "score": score, "text": text, "bbox": bbox})
        return {"predictions": result}