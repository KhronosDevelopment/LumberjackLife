from django.urls import path, include
from ll.views import *
import random

urlpatterns = [
    path("data/players/", data.players),
    path("data/slots/", data.slots.load),
    path("data/slots/save/", data.slots.save),
]
