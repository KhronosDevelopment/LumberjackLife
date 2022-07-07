'''
    IMPORTS
'''
from helpers import *
import kd

'''
    MODELS
'''
class Player(KDModel, ObservableModel):
    user = OneToOneField(
        kd.models.User,
        on_delete=CASCADE,
        primary_key=True,
        related_name='ll_player',
        attname='id'
    )
    
    played_in_alpha = BooleanField(null=False, blank=False, default=False)
    played_in_beta = BooleanField(null=False, blank=False, default=True)

class SaveSlot(KDModel, ObservableModel):
    player = ForeignKey(
        Player,
        on_delete=CASCADE,
        related_name='slots'
    )
    
    index = PositiveIntegerField(null=False)
    
    @cleaner('index', int)
    def clean_index(index):
        if 1 <= index <= 5:
            return index
        
        raise CannotCleanField(f"Must be between 1 and 5")
    
    @cleaner('data', object)
    def clean_data(data):
        if data is None:
            raise CannotCleanField(f"Cannot be empty")
        
        return data
    
    class Meta:
        unique_together = ('player', 'index')

class SaveSlotData(KDModel):
    slot = OneToOneField(
        SaveSlot,
        on_delete=CASCADE,
        primary_key=True,
        related_name='data',
        attname='slot_id'
    )
    
    json = JSONField(null=False, default=dict)
