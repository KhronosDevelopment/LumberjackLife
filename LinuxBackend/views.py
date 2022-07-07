'''
    IMPORTS
'''
from helpers import *
from ll.models import *

'''
    VIEWS
'''
class data(Endpoint):
    @view(verbs=['GET'])
    def players(request):
        player = request.user.get_player('ll')
        
        new = not player
        if new:
            player = Player(
                user=request.user
            )
        
        player.observe()
        if new:
            player.create()
        else:
            player.update()
        
        return Response(player.export(recurse='slots'))
    
    class slots:
        @view(
            verbs=['GET'],
            auth_player='ll',
            params={
                'index': SaveSlot.clean_index,
            }
        )
        def load(request, params):
            try:
                save_slot = request.player.slots.get(index=params.index)
                assert hasattr(save_slot, 'data')
            except (SaveSlot.DoesNotExist, AssertionError):
                return Response({'detail': 'slot corrupted or does not exist'}, status=404)
            
            return Response(save_slot.data.json)
        
        @view(
            verbs=['POST'],
            auth_player='ll',
            params={
                'index': SaveSlot.clean_index,
                'data': TypeCleaner(dict)
            }
        )
        def save(request, params):
            try:
                save_slot = request.player.slots.get(index=params.index)
            except SaveSlot.DoesNotExist:
                with DBTransaction():
                    save_slot = SaveSlot(
                        player = request.player,
                        index = params.index,
                        data = SaveSlotData(
                            json = params.data
                        )
                    )
                    save_slot.create()
                    
                    save_slot.data.slot = save_slot
                    save_slot.data.create()
            else:
                with DBTransaction():
                    if hasattr(save_slot, 'data'):
                        save_slot.data.json = params.data
                        save_slot.data.update()
                    else:
                        save_slot.data = SaveSlotData(json=params.data, slot=save_slot)
                        save_slot.data.create()
                    
                    save_slot.observe()
                    save_slot.update()
            
            request.player.refresh_from_db()
            return Response(request.player.export(recurse='slots'))
