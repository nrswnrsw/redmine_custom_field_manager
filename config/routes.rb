# frozen_string_literal: true

put 'custom_field_manager/custom_fields/order',
    :to => 'rcfm/custom_fields#update_order',
    :as => 'rcfm_custom_field_order'

put 'custom_field_manager/custom_fields/:custom_field_id/enumerations',
    :to => 'rcfm/enumerations#update',
    :as => 'rcfm_custom_field_enumerations'

get 'custom_field_manager/custom_fields/:custom_field_id/enumerations.csv',
    :to => 'rcfm/enumerations#export',
    :as => 'rcfm_export_custom_field_enumerations'

post 'custom_field_manager/custom_fields/:custom_field_id/enumerations/import/preview',
     :to => 'rcfm/enumerations#import_preview',
     :as => 'rcfm_preview_custom_field_enumerations_import'

post 'custom_field_manager/custom_fields/:custom_field_id/enumerations/import',
     :to => 'rcfm/enumerations#import',
     :as => 'rcfm_import_custom_field_enumerations'

get 'custom_field_manager/history',
    :to => 'rcfm/histories#index',
    :as => 'rcfm_histories'

get 'custom_field_manager/history/:id',
    :to => 'rcfm/histories#show',
    :as => 'rcfm_history'

delete 'custom_field_manager/history',
       :to => 'rcfm/histories#destroy',
       :as => 'rcfm_delete_histories'

post 'custom_field_manager/history/cleanup',
     :to => 'rcfm/histories#cleanup',
     :as => 'rcfm_cleanup_histories'

post 'custom_field_manager/history/:id/restore/preview',
     :to => 'rcfm/histories#restore_preview',
     :as => 'rcfm_preview_history_restore'

post 'custom_field_manager/history/:id/restore',
     :to => 'rcfm/histories#restore',
     :as => 'rcfm_restore_history'
