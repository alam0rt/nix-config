{
  pkgs,
  config,
  ...
}: {
  home.packages = with pkgs; [brewtarget];
  xdg = {
    configFile = {
      "brewtarget/brewtargetPersistentSettings.conf" = {
        enable = true;
        text = ''
          [General]
          LogDirectory=${config.xdg.configHome}/brewtarget
          BackupDirectory=/mnt/share/${config.home.username}/brewing/brewtarget_backups
          check_version=false
          color_formula=ebc
          config_version=1
          date_format=256
          dbType=1
          geometry=@ByteArray(\x1\xd9\xd0\xcb\0\x3\0\0\0\0\0\0\0\0\0\x1b\0\0\a\x7f\0\0\x4\x37\0\0\0\0\0\0\0\x33\0\0\a}\0\0\x4\x35\0\0\0\0\x2\0\0\0\a\x80\0\0\0\0\0\0\0\x33\0\0\a\x7f\0\0\x4\x37)
          ibu_formula=tinseth
          language=en
          recipeKey=30
          unitSystem_acidity=acidity_pH
          unitSystem_bitterness=bitterness_InternationalBitternessUnits
          unitSystem_carbonation=carbonation_Volumes
          unitSystem_color=color_StandardReferenceMethod
          unitSystem_count=count_NumberOf
          unitSystem_density=density_SpecificGravity
          unitSystem_diastaticPower=diastaticPower_Lintner
          unitSystem_length=length_Metric
          unitSystem_massFractionOrConc=massFractionOrConc_Brewing
          unitSystem_specificHeatCapacity=specificHeatCapacity_Calories
          unitSystem_specificVolume=specificVolume_Metric
          unitSystem_temperature=temperature_MetricIsCelsius
          unitSystem_time=time_CoordinatedUniversalTime
          unitSystem_viscosity=viscosity_Metric
          unitSystem_volume=volume_Metric
          unitSystem_weight=mass_Metric
          windowState=@ByteArray(\0\0\0\xff\0\0\0\0\xfd\0\0\0\0\0\0\a\x80\0\0\x3\xb3\0\0\0\x4\0\0\0\x4\0\0\0\b\0\0\0\b\xfc\0\0\0\x1\0\0\0\x2\0\0\0\x1\0\0\0\xe\0t\0o\0o\0l\0\x42\0\x61\0r\x1\0\0\0\0\xff\xff\xff\xff\0\0\0\0\0\0\0\0)

          [EquipmentEditor]
          label_mashTunSpecificHeat_unit=SpecificHeatCapacityCalories

          [MainWindow]
          boilStepTableWidget_headerState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x3\xd9\0\0\0\n\0\x1\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x84\0\0\0\0\0\0\0\n\0\0\0\xba\0\0\0\x1\0\0\0\0\0\0\0N\0\0\0\x1\0\0\0\0\0\0\0U\0\0\0\x1\0\0\0\0\0\0\0V\0\0\0\x1\0\0\0\0\0\0\0K\0\0\0\x1\0\0\0\0\0\0\0\x62\0\0\0\x1\0\0\0\0\0\0\0X\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0[\0\0\0\x1\0\0\0\0\0\0\0\x62\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
          fermentationStepTableWidget_headerState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x3\x10\0\0\0\n\0\x1\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x84\0\0\0\0\0\0\0\n\0\0\0.\0\0\0\x1\0\0\0\0\0\0\0N\0\0\0\x1\0\0\0\0\0\0\0U\0\0\0\x1\0\0\0\0\0\0\0K\0\0\0\x1\0\0\0\0\0\0\0\x62\0\0\0\x1\0\0\0\0\0\0\0X\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0[\0\0\0\x1\0\0\0\0\0\0\0H\0\0\0\x1\0\0\0\0\0\0\0\x33\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
          mashStepTableWidget_headerState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x2N\0\0\0\x6\0\x1\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x84\0\0\0\0\0\0\0\x6\0\0\0R\0\0\0\x1\0\0\0\0\0\0\0\x8f\0\0\0\x1\0\0\0\0\0\0\0L\0\0\0\x1\0\0\0\0\0\0\0k\0\0\0\x1\0\0\0\0\0\0\0^\0\0\0\x1\0\0\0\0\0\0\0X\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
          splitter_horizontal_State=@ByteArray(\0\0\0\xff\0\0\0\x1\0\0\0\x2\0\0\x1h\0\0\x1#\x1\xff\xff\xff\xff\x1\0\0\0\x2\0)
          splitter_vertical_State=@ByteArray(\0\0\0\xff\0\0\0\x1\0\0\0\x2\0\0\x1\x44\0\0\x2\a\x1\xff\xff\xff\xff\x1\0\0\0\x1\0)
          treeView_equip_headerState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\x1\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\xb1\0\0\0\x2\x1\x1\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\x2\0\0\0M\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\x64\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
          treeView_ferm_headerState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x2\x31\0\0\0\x3\x1\x1\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\x3\0\0\x1i\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\x64\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
          treeView_hops_headerState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x2 \0\0\0\x4\x1\x1\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\x4\0\0\0\xf4\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\x64\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
          treeView_misc_headerState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1H\0\0\0\x2\x1\x1\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\x2\0\0\0\xe4\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\x64\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
          treeView_recipe_headerState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1\xa4\0\0\0\x4\x1\x1\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\x4\0\0\0x\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\x64\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
          treeView_style_headerState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x2\xcc\0\0\0\x5\x1\x1\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\x5\0\0\x1<\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\x64\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)
          treeView_yeast_headerState=@ByteArray(\0\0\0\xff\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x2\xf9\0\0\0\x5\x1\x1\0\x1\0\0\0\0\0\0\0\0\0\0\0\0\x64\xff\xff\xff\xff\0\0\0\x81\0\0\0\0\0\0\0\x5\0\0\x1i\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\0\x64\0\0\0\x1\0\0\0\0\0\0\x3\xe8\0\0\0\0\x64\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x1)

          [backups]
          count=2
        '';
      };
    };
  };
}
