#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasInit { } {

    #--- source files we need.
    source $::env(SLICER_HOME)/../Slicer3/Modules/QueryAtlas/Tcl/QueryAtlasWeb.tcl
    source $::env(SLICER_HOME)/../Slicer3/Modules/QueryAtlas/Tcl/QueryAtlasControlledVocabulary.tcl
    source $::env(SLICER_HOME)/../Slicer3/Modules/QueryAtlas/Tcl/Card.tcl
    source $::env(SLICER_HOME)/../Slicer3/Modules/QueryAtlas/Tcl/CardFan.tcl
    QueryAtlasInitializeGlobals
}



#----------------------------------------------------------------------------------------------------
# 
# 
#----------------------------------------------------------------------------------------------------
proc QueryAtlasInitializeGlobals { } {

    #--- initialize globals
    set ::QA(linkBundleCount) 0

    set ::QA(SceneLoaded) 0
    set ::QA(annotations) ""
    set ::QA(modelNodeID) ""
    set ::QA(modelDisplayNodeID) ""
    set ::QA(labelMap) ""
    set ::QA(CurrentRASPoint) ""
    set ::QA(brain,volumeNodeID) ""
    set ::QA(statvol,volumeNodeID) ""
    set ::QA(label,volumeNodeID) ""

    set ::QA(ontologyHost ) "localhost"
    set ::QA(ontologyPort) 3334
    set ::QA(ontologyViewerPID) ""
    set ::QA(ontologyLaunched) 0

    set ::QA(annotationVisibility) 1
}



#----------------------------------------------------------------------------------------------------
# pops up a message when there's a problem
# str is a text string containing the message
#----------------------------------------------------------------------------------------------------
proc QueryAtlasMessagDialog { str } {

    #--- convenience method for displaying popup message dialog.
        set dialog [ vtkKWMessageDialog New ]
        $dialog SetParent [ $::slicer3::ApplicationGUI GetMainSlicerWindow ]
        $dialog SetStyleToMessage
        $dialog SetText $str
        $dialog Create
        $dialog Invoke
        $dialog Delete
}





#----------------------------------------------------------------------------------------------------
#--- tries to put a brain in the background,
#--- a label map in the label layer and
#--- a statistics volume in the foreground.
#--- looks in the various node names for clues.
#--- makes no changes if it can't find a dataset.
#----------------------------------------------------------------------------------------------------
proc QueryAtlasTryConfigure { } {

    set found [ QueryAtlasAutoConfigureLayers ]
    if {!found } {
        QueryAtlasMessageDialog "Couldn't auto-detect model and label map. Please use selectors to specify."
        return
    }
    set found [ QueryAtlasAddAnnotations  ]
    if { !found } {
        QueryAtlasMessageDialog "Couldn't find annotations for the selected model or label map. This scene may not support interactive annotations."
        return
    }

    QueryAtlasAutoWinLevThreshStats
    QueryAtlasInitializePicker 
    QueryAtlasRenderView
    QueryAtlasUpdateCursor
    set ::QA(CurrentRASPoint) "0 0 0"
    set ::QA(SceneLoaded) 1
}

#----------------------------------------------------------------------------------------------------
# --- applies some display parameters to volumes that could be statistics...
#----------------------------------------------------------------------------------------------------
proc QueryAtlasAutoWinLevThreshStats { } {
    set numVnodes  [ $::slicer3::MRMLScene GetNumberOfNodesByClass "vtkMRMLVolumeNode" ]
    set numCnodes [$::slicer3::MRMLScene GetNumberOfNodesByClass "vtkMRMLSliceCompositeNode"]
    
    for { set i 0 } { $i < $numVnodes } { incr i } {
        #--- get names of all volume nodes in scene
        set node [ $::slicer3::MRMLScene GetNthNodeByClass $i "vtkMRMLVolumeNode" ]
        if { $node != "" } {
            set name [ $node GetName ]
        }
        set t [ string first "stat" $name ]
        if {$t >= 0 } {
            set gotstats 1
            set ::QA(statvol,volumeNodeID) [ $node GetID ]

            #--- TODO: choose ballpark window level and threshold for stats.
            set vnode [ $::slicer3::MRMLScene GetNodeByID $::QA(statvol,volumeNodeID) ]
            set volumeDisplayNode [ $vnode GetDisplayNode ]

            #--- set these guys manually...
            $volumeDisplayNode SetAutoThreshold 0
            $volumeDisplayNode SetAutoWindowLevel 0

            if { 0 } {
            set window [ $volumeDisplayNode GetWindow ]
            set level [ $volumeDisplayNode GetLevel ]
            set upperT [$volumeDisplayNode GetUpperThreshold]
            set lowerT [$volumeDisplayNode GetLowerThreshold]
            #--- set window... hmmm.
            $volumeDisplayNode SetWindow [ expr $window / 2.5 ]
            set window [ $volumeDisplayNode GetWindow ]
            $volumeDisplayNode SetLevel [ expr $upperT - ( $window / 2.0 ) ]
            #--- set lower threshold
            set lowerT [ expr $upperT - (( $upperT - $lowerT ) / 2.5 ) ]
            $volumeDisplayNode SetLowerThreshold $lowerT
            $volumeDisplayNode SetLowerThreshold $upperT
            #--- apply the settings
            $volumeDisplayNode SetApplyThreshold 1
            $volumeDisplayNode SetAutoThreshold 0
            }

        }
    }
    
}


#----------------------------------------------------------------------------------------------------
#--- tries to put a brain in the background,
#--- a label map in the label layer and
#--- a statistics volume in the foreground.
#--- looks in the various node names for clues.
#--- makes no changes if it can't find a dataset.
#----------------------------------------------------------------------------------------------------
proc QueryAtlasAutoConfigureLayers { } {

    #--- look in volume nodes for "brain", for "aseg" and for "stat"
    #--- put the first of each found in appropriate layer,
    #--- and if none found, leave layers as they are.
    #--- TODO: build this out for other queriable datasets.
    #--- TODO: apply good window, level and threshold values here.
    set numVnodes  [ $::slicer3::MRMLScene GetNumberOfNodesByClass "vtkMRMLVolumeNode" ]
    set numCnodes [$::slicer3::MRMLScene GetNumberOfNodesByClass "vtkMRMLSliceCompositeNode"]
    set numMnodes [$::slicer3::MRMLScene GetNumberOfNodesByClass "vtkMRMLModelNode"]

    set gotbrain 0
    set gotlabels 0
    set gotstats 0
    set gotmodel 0
    for { set i 0 } { $i < $numVnodes } { incr i } {
        #--- get names of all volume nodes in scene
        set node [ $::slicer3::MRMLScene GetNthNodeByClass $i "vtkMRMLVolumeNode" ]
        if { $node != "" } {
            set name [ $node GetName ]
        }
        #--- now check on name
        if { ! $gotbrain } {
            set t [ string first "brain" $name ]
            if { $t >= 0 } {
                set gotbrain 1
                set ::QA(brain,volumeNodeID) [ $node GetID ]
                #--- put in background
                for { set j 0 } { $j < $numCnodes } { incr j } {
                    set cnode [$::slicer3::MRMLScene GetNthNodeByClass $j "vtkMRMLSliceCompositeNode"]
                    $cnode SetReferenceBackgroundVolumeID $::QA(brain,volumeNodeID)
                }
                #--- TODO: Set auto threshold on.
            }
        }
        if { ! $gotlabels } {
            set t [ string first "aseg" $name ]
            if { $t >= 0 } {
                set gotlabels 1
                set ::QA(label,volumeNodeID) [ $node GetID ]
                #--- put in label layer
                for { set j 0 } { $j < $numCnodes } { incr j } {
                    set cnode [$::slicer3::MRMLScene GetNthNodeByClass $j "vtkMRMLSliceCompositeNode"]
                    $cnode SetReferenceLabelVolumeID $::QA(label,volumeNodeID)
                    $cnode SetLabelOpacity 0.5
                }
                #-- if we found it, set the aseg node selector in the GUI
                set as [$::slicer3::QueryAtlasGUI GetFSasegSelector]
                $as SetSelected $node
            }
        }
        if { ! $gotstats } {
            set t [ string first "stat" $name ]
            if {$t >= 0 } {
                set gotstats 1
                set ::QA(statvol,volumeNodeID) [ $node GetID ]
                #--- put in foreground
                for { set j 0 } { $j < $numCnodes } { incr j } {
                    set cnode [$::slicer3::MRMLScene GetNthNodeByClass $j "vtkMRMLSliceCompositeNode"]
                    $cnode SetReferenceForegroundVolumeID $::QA(statvol,volumeNodeID)
                    $cnode SetForegroundOpacity 1
                }
            }
        }
    }
    for { set i 0 } { $i < $numMnodes } { incr i } {
        #--- get names of all volume nodes in scene
        set node [ $::slicer3::MRMLScene GetNthNodeByClass $i "vtkMRMLModelNode" ]
        if { $node != "" } {
            set name [ $node GetName ]
        }
        if {! $gotmodel } {
            set t [ string first "lh.pial" $name ]
            if {$t >= 0 } {
                set gotmodel 1
                set ::QA(modelNodeID) [ $node GetID ]
                set ::QA(modelDisplayNodeID) [ $node GetDisplayNodeID ]
                #-- if we found it, set the model node selector in the GUI
                set ms [$::slicer3::QueryAtlasGUI GetFSmodelSelector]
                $ms SetSelected $node
            }
        }
        if {! $gotmodel } {
            set t [ string first "rh.pial" $name ]
            if {$t >= 0 } {
                set gotmodel 1
                set ::QA(modelNodeID) [ $node GetID ]
                set ::QA(modelDisplayNodeID) [ $node GetDisplayNodeID ]
                #-- if we found it, set the model node selector in the GUI
                set ms [$::slicer3::QueryAtlasGUI GetFSmodelSelector]
                $ms SetSelected $node
            }
        }
    }

    #--- if we couldn't find model or labels return 0
    #--- These are necessary for generating annotations
    if { (! $gotmodel) || (! $gotlabels)  } {
        return 0
    } else {
        return 1
    }
}





#----------------------------------------------------------------------------------------------------
#--- gets the label map to use for interactive display
#----------------------------------------------------------------------------------------------------
proc QueryAtlasGetLabels { } {

    $::slicer3::ApplicationGUI SelectModule QueryAtlas
    set as [$::slicer3::QueryAtlasGUI GetFSasegSelector]
    set vnode [ $as GetSelected ]
    if { $vnode == "" } {
        QueryAtlasMessageDialog "Use this menubutton to choose a label map."
        return
    }
    set ::QA(label,volumeNodeID) [ $vnode GetID ]

    #--- now put label map in label layer.
    #--- put in label layer
    for { set j 0 } { $j < $numCnodes } { incr j } {
        set cnode [$::slicer3::MRMLScene GetNthNodeByClass $j "vtkMRMLSliceCompositeNode"]
        $cnode SetReferenceLabelVolumeID $::QA(label,volumeNodeID)
        $cnode SetLabelOpacity 0.5
    }
    
}





#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasLoad { {filename ""} } {

    # find the data
    set ::QA(annotations) ""
    set ::QA(linkBundleCount) 0
    set ::QA(SceneLoaded) 0
    
    if { $filename != "" } {
        set ::QA(annotations) $filename
    } else {
        set candidates {
            c:/cygwin/home/wjp/data/fBIRN-AHM2006/fbph2-000670986943/surf/lh.pial
            /workspace/pieper/fBIRN-AHM2006/fbph2-000670986943/surf/lh.pial
            /projects/birn/data/fBIRN-AHM2006/fbph2-000670986943/surf/lh.pial
            i:/fBIRN-AHM2006/fbph2-000670986943/surf/lh.pial
            c:/data/fBIRN-AHM2006/fbph2-000648622547/surf/lh.pial
            /projects/birn/freesurfer/data/bert/surf/lh.pial
        }
        foreach c $candidates {
            if { [file exists $c] } {
                set ::QA(annotations) $c
                set ::QA(directory) [file dirname [file dirname $::QA(annotations)]]
                break
            }
        }
    }

    QueryAtlasAddBIRNLogo
    QueryAtlasAddModel
    QueryAtlasAddVolumes
    QueryAtlasAddAnnotations 
    QueryAtlasInitializePicker 
    QueryAtlasRenderView
    QueryAtlasUpdateCursor
    set ::QA(CurrentRASPoint) "0 0 0"
    set ::QA(SceneLoaded) 1
}





#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasAddBIRNLogo {} {

  set renderWidget [[$::slicer3::ApplicationGUI GetViewerWidget] GetMainViewer]
  set interactor [$renderWidget GetRenderWindowInteractor] 

  #
  # add the BIRN logo if possible (logo widget was added
  # after VTK 5, so not included in some builds)
  #
  if { [info command vtkLogoWidget] != "" } {

    # Logo
    set logoFile $::SLICER_BUILD/../Slicer3/Libs/FreeSurfer/Testing/birn-new-big.png
    set logoRep [vtkLogoRepresentation New]
    set reader [vtkPNGReader New]
    $reader SetFileName $logoFile
    $logoRep SetImage [$reader GetOutput]
    [$logoRep GetImageProperty] SetOpacity .75

    set logoWidget [vtkLogoWidget New]
    $logoWidget SetInteractor $interactor
    $logoWidget SetRepresentation $logoRep

    $logoWidget On
  }

  return

  #
  # generic logo setup
  # - BIRN specific config below
  #
  set reader [vtkPNGReader New]
  set texture [vtkTexture New]
  set polyData [vtkPolyData New]
  set points [vtkPoints New]
  set polys [vtkCellArray New]
  set tc [vtkFloatArray New]
  set textureMapper [vtkPolyDataMapper2D New]
  set textureActor [vtkActor2D New]
  set imageProperty [vtkProperty2D New]

  #$points SetNumberOfPoints 4
  set corners { {0.0 0.0 0.0} {1.0 0.0 0.0} {1.0 1.0 0.0} {0.0 1.0 0.0} }
  foreach corner $corners {
    eval $points InsertNextPoint $corner
  }

  $polyData SetPoints $points
  $polys InsertNextCell 4
  foreach p "0 1 2 3" {
    $polys InsertCellPoint 0
  }
  $polyData SetPolys $polys

  $tc SetNumberOfComponents 2
  $tc SetNumberOfTuples 4
  set tcs { {0.0 0.0} {1.0 0.0} {1.0 1.0} {0.0 1.0} }
  foreach tcoords $tcs point {0 1 2 3} {
    foreach i "0 1" tcoord $tcoords {
      $tc InsertComponent $point $i $tcoord
    }
  }
  [$polyData GetPointData] SetTCoords $tc

  $textureMapper SetInput $polyData
  $textureActor SetMapper $textureMapper

  $imageProperty SetOpacity 0.25


  #
  # birn logo specific
  #
  set logoFile $::SLICER_BUILD/../Slicer3/Libs/FreeSurfer/Testing/birn-new-big.png
  set ::QA(logo,actor) $textureActor

  set viewer [$::slicer3::ApplicationGUI GetViewerWidget]
  set renderWidget [$viewer GetMainViewer]
  set renderer [$renderWidget GetRenderer]
  $renderer AddActor2D $::QA(logo,actor)

  $reader Delete
  $texture Delete
  $polyData Delete
  $points Delete
  $polys Delete
  $tc Delete
  $textureMapper Delete
  $imageProperty Delete

  if { 0 } {
  #78 :  // Set up parameters from thw superclass
  #79 :double size[2];
  #80 :this->GetSize(size);
  #81 :this->Position2Coordinate->SetValue(0.04*size[0], 0.04*size[1]);
  #82 :this->ProportionalResize = 1;
  #83 :this->Moving = 1;
  #84 :this->ShowBorder = vtkBorderRepresentation::BORDER_ACTIVE;
  #85 :this->PositionCoordinate->SetValue(0.9, 0.025);
  #86 :this->Position2Coordinate->SetValue(0.075, 0.075); 
  }
}



#----------------------------------------------------------------------------------------------------
#--- Add the model with the filename to the scene
#----------------------------------------------------------------------------------------------------
proc QueryAtlasAddModel {} {

  # load the data
  set modelNode [vtkMRMLModelNode New]
  set modelStorageNode [vtkMRMLFreeSurferModelStorageNode New]
  set modelDisplayNode [vtkMRMLModelDisplayNode New]

  $modelStorageNode SetFileName $::QA(annotations)
  $modelStorageNode SetUseStripper 0

  if { [$modelStorageNode ReadData $modelNode] != 0 } {
    $modelNode SetName [file tail $::QA(annotations)]

    $modelNode SetScene $::slicer3::MRMLScene
    $modelStorageNode SetScene $::slicer3::MRMLScene
    $modelDisplayNode SetScene $::slicer3::MRMLScene

    $::slicer3::MRMLScene AddNode $modelStorageNode
    $::slicer3::MRMLScene AddNode $modelDisplayNode

    $modelNode SetReferenceStorageNodeID [$modelStorageNode GetID]
    $modelNode SetAndObserveDisplayNodeID [$modelDisplayNode GetID]

    $::slicer3::MRMLScene AddNode $modelNode
    set ::QA(modelNodeID) [$modelNode GetID]
  } else {
    puts stderr "Can't read model $::QA(annotations)"
  }

  $modelNode Delete
  $modelStorageNode Delete
  $modelDisplayNode Delete
}

#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasAddVolumes {} {

  set volumesLogic [$::slicer3::VolumesGUI GetLogic]
  set colorLogic [$::slicer3::ColorGUI GetLogic]
  set centered 1

  #
  # add the brain image
  #
  set fileName $::QA(directory)/mri/brain.mgz

  set volumeNode [$volumesLogic AddArchetypeVolume $fileName $centered 0 brain]

  set ::QA(brain,volumeNodeID) [$volumeNode GetID]

  set volumeDisplayNode [$volumeNode GetDisplayNode]

  $volumeDisplayNode SetAndObserveColorNodeID [$colorLogic GetDefaultVolumeColorNodeID]

  $volumeDisplayNode SetWindow 216
  $volumeDisplayNode SetLevel 108
  $volumeDisplayNode SetUpperThreshold 216
  $volumeDisplayNode SetLowerThreshold 30.99
  $volumeDisplayNode SetApplyThreshold 1
  $volumeDisplayNode SetAutoThreshold 0

  #
  # add the function image
  # - requires translation to correct space
  #
  #--- hardcoded transform!
  #---TODO: get this from data
  set transformNode [vtkMRMLLinearTransformNode New]
  set matrix [$transformNode GetMatrixTransformToParent]
  $matrix Identity
  $matrix SetElement 0 3  6
  $matrix SetElement 1 3  13
  $matrix SetElement 2 3  13
  $::slicer3::MRMLScene AddNode $transformNode


  set fileName [file dirname $::QA(directory)]/sirp-hp65-stc-to7-gam.feat/stats/zstat8.nii

  set volumeNode [$volumesLogic AddArchetypeVolume $fileName $centered 0 zstat8]
  $volumeNode SetAndObserveTransformNodeID [$transformNode GetID]
  set ::QA(statvol,volumeNodeID) [$volumeNode GetID]
  set volumeDisplayNode [$volumeNode GetDisplayNode]
  $volumeDisplayNode SetAndObserveColorNodeID "vtkMRMLColorTableNodeIron"
  $volumeDisplayNode SetWindow 3.3
  $volumeDisplayNode SetLevel 3
  $volumeDisplayNode SetUpperThreshold 6.8
  $volumeDisplayNode SetLowerThreshold 1.34
  $volumeDisplayNode SetApplyThreshold 1


  #
  # add the segmentation image
  #


  set fileName $::QA(directory)/mri/aparc+aseg.mgz
  set volumeNode [$volumesLogic AddArchetypeVolume $fileName $centered 1 aparc+aseg]
  set ::QA(label,volumeNodeID) [$volumeNode GetID]

  set volumeDisplayNode [$volumeNode GetDisplayNode]

  $volumeDisplayNode SetAndObserveColorNodeID [$colorLogic GetDefaultFreeSurferLabelMapColorNodeID]

  #
  # make brain be background, functional foreground, and segmentation be label map
  #
  set nNodes [$::slicer3::MRMLScene GetNumberOfNodesByClass "vtkMRMLSliceCompositeNode"]
  for { set i 0 } { $i < $nNodes } { incr i } {
    set cnode [$::slicer3::MRMLScene GetNthNodeByClass $i "vtkMRMLSliceCompositeNode"]
    $cnode SetReferenceBackgroundVolumeID $::QA(brain,volumeNodeID)
    $cnode SetReferenceForegroundVolumeID $::QA(statvol,volumeNodeID)
    $cnode SetReferenceLabelVolumeID $::QA(label,volumeNodeID)
    $cnode SetForegroundOpacity 1
    $cnode SetLabelOpacity 0.5
  }
}



#----------------------------------------------------------------------------------------------------
#--- use the freesurfer annotation code to put 
#--- label scalars onto the model
#----------------------------------------------------------------------------------------------------
proc QueryAtlasAddAnnotations { } {
    
    #set fileName [file dirname $::QA(annotations)]/../label/lh.aparc.annot

    if { $::QA(modelNodeID) != "" } {
        #--- get the model out of the scene
        set modelNode [$::slicer3::MRMLScene GetNodeByID $::QA(modelNodeID)]
        set displayNodeID [$modelNode GetDisplayNodeID]
        set displayNode [$::slicer3::MRMLScene GetNodeByID $displayNodeID]
        set storageNode [ $modelNode GetStorageNode ]
        set viewer [$::slicer3::ApplicationGUI GetViewerWidget] 
        $viewer UpdateFromMRML
        #set actor [ $viewer GetActorByID [$modelNode GetID] ]
        set actor [ $viewer GetActorByID $displayNodeID ]
        if { $actor == "" } {
            puts "can't find model as actor"
            return
        }
        set mapper [$actor GetMapper]

        #--- get name of label file
        set fileName [$storageNode GetFileName ]
        if { [ string first "aparc.annot" $fileName ] < 0 } {
            QueryAtlasMessageDialog "No appropriate annotation file is found for [$modelNode GetName]. Try selecting an annotated model, or loading the scalar overlay for this model again."
            return
        }

        if { [file exists $fileName] } {
            set polydata [$modelNode GetPolyData]
            set scalaridx [[$polydata GetPointData] SetActiveScalars "labels"]
            [$modelNode GetDisplayNode] SetActiveScalarName "labels"
            [$modelNode GetDisplayNode] SetScalarVisibility 1

            if { $scalaridx == "-1" } {
                set scalars [vtkIntArray New]
                $scalars SetName "labels"
                [$polydata GetPointData] AddArray $scalars
                [$polydata GetPointData] SetActiveScalars "labels"
                $scalars Delete
            } 
            set scalaridx [[$polydata GetPointData] SetActiveScalars "labels"]
            set scalars [[$polydata GetPointData] GetArray $scalaridx]

            set lutNode [vtkMRMLColorTableNode New]
            $lutNode SetTypeToUser
            $::slicer3::MRMLScene AddNode $lutNode
            [$modelNode GetDisplayNode] SetAndObserveColorNodeID [$lutNode GetID]

            set fssar [vtkFSSurfaceAnnotationReader New]

            $fssar SetFileName $fileName
            $fssar SetOutput $scalars
            $fssar SetColorTableOutput [$lutNode GetLookupTable]
            # try reading an internal colour table first
            $fssar UseExternalColorTableFileOff

            set retval [$fssar ReadFSAnnotation]

            array unset _labels
            if {$retval == 6} {
                error "ERROR: no internal colour table, using default"
                # use the default colour node
                [$modelNode GetDisplayNode] SetAndObserveColorNodeID [$colorLogic GetDefaultFreeSurferSurfaceLabelsColorNodeID]
                set lutNode [[$modelNode GetDisplayNode] GetColorNode]
                # get the names 
                for {set i 0} {$i < [$lutNode GetNumberOfColors]} {incr i} {
                    set _labels($i) [$lutNode GetColorName $i]
                }
            } else {
                # get the colour names from the reader       
                array set _labels [$fssar GetColorTableNames]        
            }
            array unset ::vtkFreeSurferReadersLabels_$::QA(modelNodeID)
            array set ::vtkFreeSurferReadersLabels_$::QA(modelNodeID) [array get _labels]

            # print them out
            set ::QA(labelMap) [array get _labels]

            set entries [lsort -integer [array names _labels]]

            # set the look up table
            $mapper SetLookupTable [$lutNode GetLookupTable]

            # make the scalars visible
            $mapper SetScalarRange  [lindex $entries 0] [lindex $entries end]
            $mapper SetScalarVisibility 1

            [$modelNode GetDisplayNode] SetScalarRange [lindex $entries 0] [lindex $entries end]

            $lutNode Delete
            $fssar Delete
            [$viewer GetMainViewer] Reset
        } else {
            return 0
        }

        #
        # read the freesurfer labels for the aseg+aparc
        #
        set lutFile $::SLICER_BUILD/../Slicer3/Libs/FreeSurfer/FreeSurferColorLUT.txt
        if { [file exists $lutFile] } {
            set fp [open $lutFile "r"]
            while { ![eof $fp] } {
                gets $fp line
                if { [scan $line "%d %s %d %d %d" label name r g b] == 5 } {
                    set ::QAFS($label,name) $name
                    set ::QAFS($label,rgb) "$r $g $b"
                    puts "$name -- $r $g $b"
                }
            }
            close $fp
        } else {
            QueryAtlasMessageDialog "Color lookup table $lutFile not found."
        }
        return 1
    } else {
        return 0
    }
}



#----------------------------------------------------------------------------------------------------
#--- convert a number to an RGBA 
#--- : A is always 255 (on transp)
#--- : number is incremented first so that 0 means background
#----------------------------------------------------------------------------------------------------
proc QueryAtlasNumberToRGBA {number} {
  set number [expr $number + 1]
  set r [expr $number / (256 * 256)]
  set number [expr $number % (256 * 256)]
  set g [expr $number / 256]
  set b [expr $number % 256]

  return "$r $g $b 255"
}

#----------------------------------------------------------------------------------------------------
#--- convert a RGBA to number
#--- : decrement by 1 to avoid ambiguity, since 0 is background
#----------------------------------------------------------------------------------------------------
proc QueryAtlasRGBAToNumber {rgba} {
  foreach {r g b a} $rgba {}
  return [expr $r * (256*256) + $g * 256 + $b - 1] 
}



#----------------------------------------------------------------------------------------------------
#--- set up a picking version of the polyData that can be used
#--- to render to the back buffer
#----------------------------------------------------------------------------------------------------
proc QueryAtlasInitializePicker {} {

  #
  # add a prop picker to figure out if the mouse is actually over the model
  # and to identify the slice planes
  # and a pickRenderer and picker to find the actual world space pick point
  # under the mouse for a slice plane
  #
  set ::QA(propPicker) [vtkPropPicker New]
  set ::QA(cellPicker) [vtkCellPicker New]

  #
  # get the polydata for the model
  # - model node comes from the scene (retrieved by the ID)
  # - actor comes from the main Viewer
  # - mapper comes from the actor
  #
  set modelNode [$::slicer3::MRMLScene GetNodeByID $::QA(modelNodeID)]
  set ::QA(polyData) [vtkPolyData New]
  $::QA(polyData) DeepCopy [$modelNode GetPolyData]
  set ::QA(actor) [vtkActor New]
  set ::QA(mapper) [vtkPolyDataMapper New]
  $::QA(mapper) SetInput $::QA(polyData)
  $::QA(actor) SetMapper $::QA(mapper)

  #
  # instrument the polydata with cell number colors
  # - note: even though the array is named CellNumberColors here,
  #   vtk will (sometimes?) rename it to "Opaque Colors" as part of the first 
  #   render pass
  #

  $::QA(polyData) Update

  set cellData [$::QA(polyData) GetCellData]
  set cellNumberColors [$cellData GetArray "CellNumberColors"] 
  if { $cellNumberColors == "" } {
    set cellNumberColors [vtkUnsignedCharArray New]
    $cellNumberColors SetName "CellNumberColors"
    $cellData AddArray $cellNumberColors
    $cellData SetScalars $cellNumberColors
  }
  $cellData SetScalars $cellNumberColors

  set cellNumberColors [$cellData GetArray "CellNumberColors"] 
  $cellNumberColors Initialize
  $cellNumberColors SetNumberOfComponents 4

  set numberOfCells [$::QA(polyData) GetNumberOfCells]
  for {set i 0} {$i < $numberOfCells} {incr i} {
    eval $cellNumberColors InsertNextTuple4 [QueryAtlasNumberToRGBA $i]
  }

  set ::QA(cellData) $cellData
  set ::QA(numberOfCells) $numberOfCells

  set scalarNames {"CellNumberColors" "Opaque Colors"}
  foreach scalarName $scalarNames {
    if { [$::QA(cellData) GetScalars $scalarName] != "" } {
      $::QA(cellData) SetActiveScalars $scalarName
      break
    }
  }
  $::QA(mapper) SetScalarModeToUseCellData
  $::QA(mapper) SetScalarVisibility 1
  $::QA(mapper) SetScalarMaterialModeToAmbient
  $::QA(mapper) SetScalarRange 0 $::QA(numberOfCells)
  [$::QA(actor) GetProperty] SetAmbient 1.0
  [$::QA(actor) GetProperty] SetDiffuse 0.0

  #
  # add the mouse move callback
  # - create the classes that will be used every render and in the callback
  # - add the callback with the current render info
  #
  if { ![info exists ::QA(windowToImage)] } {
    #set ::QA(viewer) [vtkImageViewer New]
    set ::QA(windowToImage) [vtkWindowToImageFilter New]
  }
  set renderWidget [[$::slicer3::ApplicationGUI GetViewerWidget] GetMainViewer]
  set renderer [$renderWidget GetRenderer]
  set interactor [$renderWidget GetRenderWindowInteractor] 
  set style [$interactor GetInteractorStyle] 

  $interactor AddObserver EnterEvent "QueryAtlasCursorVisibility on"
  $interactor AddObserver LeaveEvent "QueryAtlasCursorVisibility off"
  $interactor AddObserver MouseMoveEvent "QueryAtlasPickCallback"
  $interactor AddObserver RightButtonPressEvent "QueryAtlasMenuCreate start"
  $interactor AddObserver RightButtonReleaseEvent "QueryAtlasMenuCreate end"
  $style AddObserver StartInteractionEvent "QueryAtlasCursorVisibility off"
  $style AddObserver EndInteractionEvent "QueryAtlasCursorVisibility on"
  $style AddObserver EndInteractionEvent "QueryAtlasRenderView"

  $renderer AddActor $::QA(actor)
  $::QA(actor) SetVisibility 1
}



#----------------------------------------------------------------------------------------------------
#--- re-render the picking model from the current camera location
#----------------------------------------------------------------------------------------------------
proc QueryAtlasRenderView {} {

  #
  # get the renderer related instances
  #
  set renderWidget [[$::slicer3::ApplicationGUI GetViewerWidget] GetMainViewer]
  set renderWindow [$renderWidget GetRenderWindow]
  set renderer [$renderWidget GetRenderer]

  #
  # draw the image and get the pixels
  # - set the render parameters to draw with the cell labels
  # - draw in the back buffer
  # - pull out the pixels
  # - restore the draw state and render
  #
  $renderWindow SetSwapBuffers 0
  set renderState [QueryAtlasOverrideRenderState $renderer]
  $renderWidget Render


  $::QA(windowToImage) SetInput [$renderWidget GetRenderWindow]

  set imageSize [lrange [[$::QA(windowToImage) GetOutput] GetDimensions] 0 1]
  if { [$renderWindow GetSize] != $imageSize } {
    $::QA(windowToImage) Delete
    set ::QA(windowToImage) [vtkWindowToImageFilter New]
    #$::QA(viewer) Delete
    #set ::QA(viewer) [vtkImageViewer New]
    $::QA(windowToImage) SetInput [$renderWidget GetRenderWindow]
  }

  #$::QA(viewer) SetColorWindow 255
  #$::QA(viewer) SetColorLevel 127.5
  $::QA(windowToImage) SetInputBufferTypeToRGBA
  $::QA(windowToImage) ShouldRerenderOn
  $::QA(windowToImage) ReadFrontBufferOff
  $::QA(windowToImage) Modified
  #$::QA(viewer) SetInput [$::QA(windowToImage) GetOutput]
  [$::QA(windowToImage) GetOutput] Update
  #$::QA(viewer) Render

  $renderWindow SetSwapBuffers 1
  QueryAtlasRestoreRenderState $renderer $renderState
  $renderWidget Render

}

#####################################

#----------------------------------------------------------------------------------------------------
#--- Override/Restore render state 
#--- : set up for rendering the cell picker and then
#---   restore the state afterwards
#----------------------------------------------------------------------------------------------------
proc QueryAtlasOverrideRenderState {renderer} {

  #
  # save the render state before overriding it with the 
  # parameters needed for cell rendering
  # - is just background color and visibility state of all actors
  #


  set actors [$renderer GetActors]
  set numberOfItems [$actors GetNumberOfItems]
  for {set i 0} {$i < $numberOfItems} {incr i} {
    set actor [$actors GetItemAsObject $i]
    set state($i,visibility) [$actor GetVisibility]
    $actor SetVisibility 0
  }

  set state(background) [$renderer GetBackground]
  $renderer SetBackground 0 0 0
  $::QA(actor) SetVisibility 1

  return [array get state]
}

#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasRestoreRenderState {renderer renderState} {

  array set state $renderState

  eval $renderer SetBackground $state(background)

  set actors [$renderer GetActors]
  set numberOfItems [$actors GetNumberOfItems]
  for {set i 0} {$i < $numberOfItems} {incr i} {
    set actor [$actors GetItemAsObject $i]
    $actor SetVisibility $state($i,visibility)
  }
  $::QA(actor) SetVisibility 0
}

#----------------------------------------------------------------------------------------------------
#--- utility routine that should be provided by vtkCell
#----------------------------------------------------------------------------------------------------
proc QueryAtlasPCoordsToWorld {cell pCoords} {
    
  if { [$cell GetClassName] != "vtkQuad" } {
    return "0 0 0"
  }

  foreach {r s t} $pCoords {}
  set rm [expr 1. - $r]
  set sm [expr 1. - $s]
  set sf0 [expr $rm * $sm]
  set sf1 [expr $r * $sm]
  set sf2 [expr $r * $s]
  set sf3 [expr $rm * $s]

  set points [$cell GetPoints]
  foreach {x0 x1 x2} "0 0 0" {}
  foreach p "0 1 2 3" {
    set point [$points GetPoint $p]
    foreach c "0 1 2" pp $point {
      set x$c [expr [set x$c] + $pp * [set sf$p]]
    }
  }
  return "$x0 $x1 $x2"
}

#----------------------------------------------------------------------------------------------------
#--- utility routine that should be provided by vtkKWRenderWidget
#----------------------------------------------------------------------------------------------------
proc QueryAtlasWorldToScreen { r a s } {

  set viewer [$::slicer3::ApplicationGUI GetViewerWidget] 
  set renderWidget [$viewer GetMainViewer]
  set camera [[$renderWidget GetRenderer] GetActiveCamera]
  set tkwindow [$renderWidget  GetWidgetName]
  set width [winfo width $tkwindow]
  set height [winfo height $tkwindow]

  set m [$camera GetCompositePerspectiveTransformMatrix [expr (1. * $width) / $height] 0 1]
  set vport [eval $m MultiplyPoint $r $a $s 1]
  set w [lindex $vport 3]
  set vx [expr [lindex $vport 0] / $w]
  set vy [expr [lindex $vport 1] / $w]


  set x [expr $width * (1. + $vx)/2.]
  set y [expr $height * (1. + $vy)/2.]

  return "$x $y"
}

proc QueryAtlasDistance { fromXY toXY } {
  set sum 0
  foreach f $fromXY t $toXY {
    set sum [expr $sum + ($f-$t)*($f-$t)]
  }
  return [expr sqrt($sum)]
}


#----------------------------------------------------------------------------------------------------
#--- query the cell number at the mouse location
#----------------------------------------------------------------------------------------------------
proc QueryAtlasPickCallback {} {

  if { ![info exists ::QA(windowToImage)] } {
    return
  }

  if { [$::QA(cursor,actor) GetVisibility] == 0 } {
    # if the cursor isn't on, don't bother to calculate labels
    return
  }


  #
  # get access to the standard view parts
  #
  set viewer [$::slicer3::ApplicationGUI GetViewerWidget] 
  set renderWidget [$viewer GetMainViewer]
  set renderWindow [$renderWidget GetRenderWindow]
  set interactor [$renderWidget GetRenderWindowInteractor] 
  set renderer [$renderWidget GetRenderer]
#  set actor [$viewer GetActorByID $::QA(modelNodeID)]
  set actor [$viewer GetActorByID $::QA(modelDisplayNodeID)]

  # if the window size has changed, re-render
  set imageSize [lrange [[$::QA(windowToImage) GetOutput] GetDimensions] 0 1]
  if { [$renderWindow GetSize] != $imageSize } {
    QueryAtlasRenderView
  }

  # 
  # get the event location
  #
  eval $interactor UpdateSize [$renderer GetSize]
  set ::QA(lastWindowXY) [$interactor GetEventPosition]
  foreach {x y} $::QA(lastWindowXY) {}
  set ::QA(lastRootXY) [winfo pointerxy [$renderWidget GetWidgetName]]

  #
  # use the prop picker to see if we're over the model, or the slices
  # - set the 'hit' variable accordingly for later processing
  #
  set ::QA(currentHit) ""
  if { [$::QA(propPicker) PickProp $x $y $renderer] } {
    set prop [$::QA(propPicker) GetViewProp]
    if { $prop == $actor} {
      set ::QA(currentHit) "QueryActor"
    } else {
      set mrmlID [$viewer GetIDByActor $prop]
      if { $mrmlID != "" } {
          if { $mrmlID == $::QA(modelNodeID) } {
              set ::QA(currentHit) "QueryActor"
          } else {
              set ::QA(currentHit) "SliceModel"
          }
      } 
    }
  } 

  #
  # set the 'pointlabels' depending on the thing picked
  #
  #---- did we hit a slice model?
  set pointLabels ""
  if { $::QA(currentHit) == "SliceModel" } {
      set node [$::slicer3::MRMLScene GetNodeByID $mrmlID]


      #--- WJPTEST 
      #--- this is now a display node.
      #--- must get the mrml node to which it belongs....
      set numMnodes [$::slicer3::MRMLScene GetNumberOfNodesByClass "vtkMRMLModelNode"]
      for { set zz 0 } { $zz < $numMnodes } { incr zz } {
          set testnode [ $::slicer3::MRMLScene GetNthNodeByClass $zz "vtkMRMLModelNode" ]          
          set testdisplayID [ $testnode GetDisplayNodeID ]
          if { $testdisplayID == $mrmlID } {
              set node $testnode
          }
      }

      
      if { $node != "" && [$node GetDescription] != "" } {
          array set nodes [$node GetDescription]
          set nodes(sliceNode) [$::slicer3::MRMLScene GetNodeByID $nodes(SliceID)]
          set nodes(compositeNode) [$::slicer3::MRMLScene GetNodeByID $nodes(CompositeID)]

          set propCollection [$::QA(cellPicker) GetPickList]
          $propCollection RemoveAllItems
          $propCollection AddItem [$::QA(propPicker) GetViewProp]
          $::QA(cellPicker) PickFromListOn
          $::QA(cellPicker) Pick $x $y 0 $renderer
          set cellID [$::QA(cellPicker) GetCellId]
          set pCoords [$::QA(cellPicker) GetPCoords]
          if { $cellID != -1 } {
              set polyData [[$prop GetMapper] GetInput]
              set cell [$polyData GetCell $cellID]
              
              #--- this gets the RAS point we're pointing to.
              set rasPoint [QueryAtlasPCoordsToWorld $cell $pCoords]
              set ::QA(CurrentRASPoint) $rasPoint

              set labelID [$nodes(compositeNode) GetLabelVolumeID]
              set nodes(labelNode) [$::slicer3::MRMLScene GetNodeByID $labelID]
              set rasToIJK [vtkMatrix4x4 New]
              $nodes(labelNode) GetRASToIJKMatrix $rasToIJK
              set ijk [lrange [eval $rasToIJK MultiplyPoint $rasPoint 1] 0 2]
              set imageData [$nodes(labelNode) GetImageData]
              foreach var {i j k} val $ijk {
                  set $var [expr int(round($val))]
              }
              set labelValue [$imageData GetScalarComponentAsDouble $i $j $k 0]
              if { [info exists ::QAFS($labelValue,name)] } {
                  if { $::QAFS($labelValue,name) == "Unknown" } {
                      set ::QA(currentHit) "QueryActor"
                  } else {
                      set pointLabels "$::QAFS($labelValue,name)"
                  }
              } else {
                  set pointLabels "label: $labelValue (no name available), ijk $ijk"
              }
              $rasToIJK Delete
          }
      }

  }

  #--- did we hit an anatomical model?
  if { $::QA(currentHit) == "QueryActor" } {
      #
      # get the color under the mouse from label image
      #
      set color ""
      foreach c {0 1 2 3} {
        lappend color [[$::QA(windowToImage) GetOutput] GetScalarComponentAsFloat $x $y 0 $c]
      }

      #
      # convert the color to a cell index and get the cooresponding
      # label names from the vertices
      #
      set cellNumber [QueryAtlasRGBAToNumber $color]
      if { $cellNumber >= 0 && $cellNumber < [$::QA(polyData) GetNumberOfCells] } {
        set cell [$::QA(polyData) GetCell $cellNumber]

        set labels [[$::QA(polyData) GetPointData] GetScalars "labels"]
        set points [$::QA(polyData) GetPoints]

        array set labelMap $::QA(labelMap)
        set pointLabels ""
        set numberOfPoints [$cell GetNumberOfPoints]

        set nearestRAS "0 0 0"
        set nearestIndex ""
        set nearestDistance 1000000

        for {set p 0} {$p < $numberOfPoints} {incr p} {
          set index [$cell GetPointId $p]
          set ras [$points GetPoint $index]
          set xy [eval QueryAtlasWorldToScreen $ras]
          set dist [QueryAtlasDistance $xy "$x $y"]
          if { $dist < $nearestDistance } {
            set nearestDistance $dist
            set nearestIndex $index
            set nearestRAS $ras
          }
        }
        
        if { $nearestIndex != "" } {
          set ::QA(CurrentRASPoint) $nearestRAS
          set pointLabel [$labels GetValue $index]
          if { [info exists labelMap($pointLabel)] } {
            set pointLabels $labelMap($pointLabel)
          } else {
            lappend pointLabels ""
          }
        }
      }
  } 

  # - nothing is hit yet, so check the cards
  if { $pointLabels == "" } {
    set card [::Card::HitTest $x $y]
    if { $card != "" } {
      set ::QA(currentHit) "Card"
      set ::QA(currentCard) $card
      set ::QA(CurrentRASPoint) [$card cget -ras]
    } else {
      set pointLabels "background"
    }
  }


  #---Before modifying freesurfer labelname,
  # get UMLS, Neuronames, BIRNLex mapping.
  #---  
  set ::QA(BirnLexLabel) [ QueryAtlasFreeSurferLabelsToBirnLexLabels $pointLabels ]
    
  #--- Now filter the freesurfer label name:
  # Modify label text to remove freesurfer-specific
  # name conventions (underbars, lh, rh, etc.)
  #---
  regsub -all -- "-" $pointLabels " " pointLabels
  regsub -all "ctx" $pointLabels "Cortex" pointLabels
  regsub -all "rh" $pointLabels "Right" pointLabels
  regsub -all "lh" $pointLabels "Left" pointLabels

  #
  # update the label
  #
  if { ![info exists ::QA(lastLabels)] } {
    set ::QA(lastLabels) ""
  }
  
  if { $pointLabels != $::QA(lastLabels) } {
    set ::QA(lastLabels) $pointLabels 
  }

  QueryAtlasUpdateCursor
}



#----------------------------------------------------------------------------------------------------
#--- master switch to turn off annotations in main viewer
#----------------------------------------------------------------------------------------------------
proc QueryAtlasSetAnnotationsInvisible { } {
    set ::QA(annotationVisibility) 0
}

#----------------------------------------------------------------------------------------------------
#--- master switch to turn on annotations in main viewer
#----------------------------------------------------------------------------------------------------
proc QueryAtlasSetAnnotationsVisibile { } {
    set ::QA(annotationVisibility) 1
}


#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasCursorVisibility { onoff } {

  if { $onoff == "on" } {
      #--- allows a master "switch" to turn off annotations
      #--- by default, they are on.
      if { $::QA(annotationVisibility) } {
           $::QA(cursor,actor) SetVisibility 1
      } else {
           $::QA(cursor,actor) SetVisibility 0
      }
  } else {
    $::QA(cursor,actor) SetVisibility 0
  }
  set viewer [$::slicer3::ApplicationGUI GetViewerWidget]
  $viewer RequestRender
}




#----------------------------------------------------------------------------------------------------
#--- Generate the text label
#----------------------------------------------------------------------------------------------------
proc QueryAtlasUpdateCursor {} {

  set viewer [$::slicer3::ApplicationGUI GetViewerWidget]
  if { ![info exists ::QA(cursor,actor)] } {

    set ::QA(cursor,actor) [vtkTextActor New]
    set ::QA(cursor,mapper) [vtkTextMapper New]
    $::QA(cursor,actor) SetMapper $::QA(cursor,mapper)
    [$::QA(cursor,actor) GetTextProperty] ShadowOn
    [$::QA(cursor,actor) GetTextProperty] SetFontSize 20
    [$::QA(cursor,actor) GetTextProperty] SetFontFamilyToTimes

    set renderWidget [$viewer GetMainViewer]
    set renderer [$renderWidget GetRenderer]
    $renderer AddActor2D $::QA(cursor,actor)

  }

  if { [info exists ::QA(lastLabels)] && [info exists ::QA(lastWindowXY)] } {
      $::QA(cursor,actor) SetInput $::QA(lastLabels) 
      #--- position the text label just higher than the cursor
      foreach {x y} $::QA(lastWindowXY) {}
      set y [expr $y + 15]
      $::QA(cursor,actor) SetPosition $x $y
      $viewer RequestRender
  } 
}



#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasMenuCreate { state } {

  set renderWidget [[$::slicer3::ApplicationGUI GetViewerWidget] GetMainViewer]
  set interactor [$renderWidget GetRenderWindowInteractor] 
  set position [$interactor GetEventPosition]
  set ::QA(cardRASAnchor) $::QA(CurrentRASPoint)

  if { ![info exists ::QA(menu,useTerms)] } {
    set ::QA(menu,useTerms) 1
  }

  #
  # save the event position when the menu action started (when the right mouse
  # button was pressed) and only post the menu if the position is the same.  
  # If they aren't the same, do nothing since this was a dolly(zoom) action.
  #
  switch $state {
    "start" {
      set ::QA(menu,startPosition) $position
    }
    "end" {
      if { $::QA(menu,startPosition) == $position } {

        if { 0 } {
          # some debugging help to see where the click point is (puts a ball at CurrentRASPoint
          set s [vtkSphereSource New]
          set m [vtkPolyDataMapper New]
          set a [vtkActor New]
          $m SetInput [$s GetOutput]
          $a SetMapper $m
          [$renderWidget GetRenderer] AddActor $a
          eval $a SetPosition $::QA(CurrentRASPoint)
          $a SetScale 5 5 5
        }


        set ::QA(menuRAS) $::QA(CurrentRASPoint)

        set parent [[$::slicer3::ApplicationGUI GetMainSlicerWindow] GetWidgetName]
        set qaMenu $parent.qaMenu
        catch "destroy $qaMenu"
        menu $qaMenu

        if { $::QA(currentHit) == "Card" } { 
          # bring up a card menu
          set topic [file root [$::QA(currentCard) cget -text]]
          $qaMenu insert end command -label "Browse $topic" -command "$::slicer3::Application OpenLink $::QA(url,EntrezLinks)"
        } else {
          # bring up a search menu

          $qaMenu insert end checkbutton -label "Use Search Terms" -variable ::QA(menu,useTerms)
          $qaMenu insert end command -label "Add To Search Terms" -command "QueryAtlasAddStructureTerms"
          $qaMenu insert end command -label "Remove All Structure Search Terms" -command "QueryAtlasRemoveStructureTerms"

          $qaMenu insert end command -label $::QA(lastLabels) -command ""
          $qaMenu insert end separator
          $qaMenu insert end command -label "Google..." -command "QueryAtlasQuery google"
          $qaMenu insert end command -label "Wikipedia..." -command "QueryAtlasQuery wikipedia"
          $qaMenu insert end command -label "PubMed..." -command "QueryAtlasQuery pubmed"
          $qaMenu insert end command -label "J Neuroscience..." -command "QueryAtlasQuery jneurosci"
          $qaMenu insert end command -label "IBVD..." -command "QueryAtlasQuery ibvd"
          $qaMenu insert end command -label "MetaSearch..." -command "QueryAtlasQuery metasearch"
        }
        
        foreach {x y} $::QA(lastRootXY) {}
        $qaMenu post $x $y
      }
    }
  }
}



#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasRemoveStructureTerms {} {

  $::slicer3::ApplicationGUI SelectModule QueryAtlas
  set mcl [[$::slicer3::QueryAtlasGUI GetStructureMultiColumnList] GetWidget]

  $mcl DeleteAllRows
}

#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasGetStructureTerms {} {

  $::slicer3::ApplicationGUI SelectModule QueryAtlas
  set mcl [[$::slicer3::QueryAtlasGUI GetStructureMultiColumnList] GetWidget]

  set terms ""
  set n [$mcl GetNumberOfRows]
  for {set i 0} {$i < $n} {incr i} {
    # TODO: figure out the mcl checkbutton access
    if { 1 || [$mcl GetCellTextAsInt $i 0] } {
      set term [$mcl GetCellText $i 1]
        if { ![string match "edit*" $term] && ($term != "") } {
              set terms "$terms+[$mcl GetCellText $i 1]"
        }
    }
  }
  set terms [ string trimleft $terms "+"]
  return $terms
}



#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasGetSubStructureTerms {} {

  $::slicer3::ApplicationGUI SelectModule QueryAtlas
  set mcl [[$::slicer3::QueryAtlasGUI GetCellMultiColumnList] GetWidget]

  set terms ""
  set n [$mcl GetNumberOfRows]
  for {set i 0} {$i < $n} {incr i} {
    # TODO: figure out the mcl checkbutton access
    if { 1 || [$mcl GetCellTextAsInt $i 0] } {
      set term [$mcl GetCellText $i 1]
      if { ![string match "edit*" $term] } {
        set terms "$terms+[$mcl GetCellText $i 1]"
      }
    }
  }
  set terms [ string trimleft $terms "+"]
  return $terms
}





#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasGetDiagnosisTerms { } {
    $::slicer3::ApplicationGUI SelectModule QueryAtlas
    set terms ""
    set mb [[$::slicer3::QueryAtlasGUI GetDiagnosisMenuButton] GetWidget]
    set terms [ $mb GetValue ]
    return $terms
}



#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasGetGenderTerms { } {
    $::slicer3::ApplicationGUI SelectModule QueryAtlas
    set terms ""
    set mb [[$::slicer3::QueryAtlasGUI GetGenderMenuButton] GetWidget]
    set terms [ $mb GetValue ]
    return $terms
}


#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasGetSpeciesTerms { } {
    $::slicer3::ApplicationGUI SelectModule QueryAtlas
    set terms ""
    set cb_h [$::slicer3::QueryAtlasGUI GetSpeciesHumanButton]
    set cb_ms [$::slicer3::QueryAtlasGUI GetSpeciesMouseButton]
    set cb_mq [$::slicer3::QueryAtlasGUI GetSpeciesMacaqueButton]
    
    set human [ $cb_h GetSelectedState ]
    set mouse [ $cb_ms GetSelectedState ]
    set macaque [ $cb_mq GetSelectedState ]

    if { $human } {
        set terms "human"
    }
    if { $mouse } {
        set terms "$terms+mouse"
    }
    if { $macaque } {
        set terms "$terms+macaque"
    }
    return $terms
}

#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasGetSearchTargets { } {

    set mb [$::slicer3::QueryAtlasGUI GetDatabasesMenuButton ]
    set target ""
    set target [ $mb GetValue ]
    return $target
}



#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasAddStructureTerms {} {

    #--- add term to listbox.
  $::slicer3::ApplicationGUI SelectModule QueryAtlas
  set mcl [[$::slicer3::QueryAtlasGUI GetStructureMultiColumnList] GetWidget]

  set i [$mcl GetNumberOfRows]
  $::slicer3::QueryAtlasGUI AddNewStructureSearchTerm $::QA(lastLabels)
  $mcl SetCellTextAsInt $i 0 1
  $mcl SetCellText $i 1 $::QA(lastLabels)

  #--- set hierarchy entry with most recently selected term
  set h_entry [$::slicer3::QueryAtlasGUI GetHierarchySearchTermEntry]
  $h_entry SetValue $::QA(lastLabels)
  
}


#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasQuery { site } {

    if { $::QA(lastLabels) == "background" || $::QA(lastLabels) == "Unknown" } {
        set terms ""
    } else {
        set terms $::QA(lastLabels)
    }

    if { $::QA(menu,useTerms) } {
        set terms "$terms+[QueryAtlasGetStructureTerms]"
    }

    regsub -all "/" $terms "+" terms
    regsub -all -- "-" $terms "+" terms
    regsub -all "ctx" $terms "cortex" terms
    regsub -all "rh" $terms "right+hemisphere" terms
    regsub -all "lh" $terms "left+hemisphere" terms

    switch $site {
        "google" {
            $::slicer3::Application OpenLink http://www.google.com/search?q=$terms
        }
        "wikipedia" {
            $::slicer3::Application OpenLink http://www.google.com/search?q=$terms+site:en.wikipedia.org
        }
        "pubmed" {
            $::slicer3::Application OpenLink \
                http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=search&db=PubMed&term=$terms
        }
        "jneurosci" {
            $::slicer3::Application OpenLink \
                http://www.jneurosci.org/cgi/search?volume=&firstpage=&sendit=Search&author1=&author2=&titleabstract=&fulltext=$terms
        }
        "ibvd" {
            regsub -all "Left\+" $terms "" terms ;# TODO ivbd has a different way of handling side
            regsub -all "left\+" $terms "" terms ;# TODO ivbd has a different way of handling side
            regsub -all "Right\+" $terms "" terms ;# TODO ivbd has a different way of handling side
            regsub -all "right\+" $terms "" terms ;# TODO ivbd has a different way of handling side
            regsub -all "\\+" $terms "," commaterms

            if { 0 } {
                set terms "human,normal,$commaterms"
                set url http://www.cma.mgh.harvard.edu/ibvd/search.php?f_submission=true&f_free=$commaterms
            } else {
                #--- this gets us the plot for a diagnosis context.
                #--- set url http://www.cma.mgh.harvard.edu/ibvd/how_big.php?structure=$terms&diagnosis=$dterms
                set url http://www.cma.mgh.harvard.edu/ibvd/how_big.php?structure=$terms
                
            }
            $::slicer3::Application OpenLink $url
        }
        "metasearch" {
            $::slicer3::Application OpenLink \
                https://loci.ucsd.edu/qametasearch/query.do?query=$terms
        }
    }
}




#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasLaunchOntologyBrowser { ontology } {

    set already_running [ QueryAtlasBirnLexViewerCheck ]
    if { already_running } {
        return
    }
    
    #--- start it up
    set ::QA(ontologyHost) "localhost"
    set ::QA(ontologyPort) 3334
    set ::QA(ontologyViewerPID ) ""
    
    #--- launch the viewer with a dataset
    if { $ontology == "BIRN" } {
        if { [ info exists ::QA(SceneLoaded) ] } {
            if { $::QA(SceneLoaded) } {
                if { [file exists $::env(SLICER_HOME)/../Slicer3/Modules/QueryAtlas/Java/birnlexvis.jar] &&
                     [file exists $::env(SLICER_HOME)/../Slicer3/Modules/QueryAtlas/Java/birnlex-demo.simple ] } {
                    set ::QA(ontologyViewerPID) [ exec java -jar $::env(SLICER_HOME)/../Slicer3/Modules/QueryAtlas/Java/birnlexvis.jar -h $::QA(ontologyHost) -p $::QA(ontologyPort) -t SlicerBIRNLex $::env(SLICER_HOME)/../Slicer3/Modules/QueryAtlas/Java/birnlex-demo.simple & ]
                    if { $::QA(ontologyViewerPID) == "" } {
                        puts "QueryAtlasLaunchBirnLexHierarchy: could not start BIRNLex Viewer."
                    } else {
                        set ::QA(ontologyLaunched) 1
                    }
                }
            }
        }
    } else if { $ontology == "NN" } {

    }
}



#----------------------------------------------------------------------------------------------------
#---TODO: test! Is the BirnLex Ontology viewer running?
#----------------------------------------------------------------------------------------------------
proc QueryAtlasBirnLexViewerCheck { } {
    set running 0

    set str ""
    if { [ info exists ::QA(ontologyViewerPID) ] } {
        #--- check to see if the PID still exists
        catch { set str [ exec ps -ef | grep birnlexvis | grep $::QA(ontologyViewerPID) ] }
        if { $str != "" } {
            set running 1
        }
    }
    return $running
}



#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasSendHierarchyCommand { args } {

    regsub -all -- " " $args "-" label

    if { [info exists ::QA(ontologyLaunched)] } {
        #--- get command from Hierarchy frame widget
        set result ""
        
        #--- translate the label throught the FS to BIRNLex converter
        set newLabel [ QueryAtlasFreeSurferLabelsToBirnLexLabels $label ]
        if { $newLabel == "" } {
            #--- if the converter didn't give us anything back, try sending the orig string
            set newLabel $label
        }
        if { $newLabel != "" } {
            #--- make search reqest to birnlexviz demo if port/host are defined
            if { [ info exists ::QA(ontologyHost) ] && [ info exists ::QA(ontologyPort) ] } {
                set ::QA(socket) [ socket $::QA(ontologyHost) $::QA(ontologyPort) ]

                #--- for now just put -- don't read from stdin
                puts $::QA(socket) $newLabel
                flush $::QA(socket)

                #            while {[gets stdin line] >= 0} {
                #                puts $::QA(socket) $newLabel
                #                flush $::QA(socket)
                #                gets $::QA(socket) thing
                #                append result $thing
                #            }
                close $::QA(socket)
            }

        }
        return $result
    }
}


#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasFreeSurferLabelsToBirnLexLabels { label } {
    
    set retLabel ""
    
    set labelTable "$::env(SLICER_HOME)/../Slicer3/Modules/QueryAtlas/Tcl/FreeSurferLabels2BirnLexLabels.txt"

    set fp [ open $labelTable r ]

    while { ! [eof $fp ] } {
        gets $fp line
        set tst [ string first $label $line ]
        if  { $tst > 0 } {
            #--- get second term in line
            set retLabel [ lindex $line 1 ]
            #--- get rid of underscores
            regsub -all -- "_" $retLabel " " retLabel
            break
        }
    }
    close $fp
    return $retLabel
}


#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasDisplayDefaultBIRNPaths { FSw, FIPSw} {

    set ::QueryAtlas(fipsDir) $::env(FIPSHOME)
    set ::QueryAtlas(fsSubjectDir) $::env(SUBJECTSHOME)

    FSw SetText $::QueryAtlas(fsSubjectDir)
    FIPSw SetText $::QueryAtlas(fipsDir)

}


#----------------------------------------------------------------------------------------------------
#---
#----------------------------------------------------------------------------------------------------
proc QueryAtlasTrimDirectoryPath { str } {

    #--- get a dir path
    #--- remove trailing "/" slashes
    set tmp [ string trim $str "/" ]
    
    #--- keep all chars up to and including the first "/"
    set index [ string first "/" $tmp ]
    if { $index >= 0 } {
        set front [ string range $tmp 0 $index ]
    } else {
        set front ""
    }
    
    #--- keep all chars after and including the last "/"
    set index2 [ string last "/" $tmp ]
    #--- if there's only one slash in path, don't trim
    if { $index2 == $index1 } {
        set trimpath $str
    } else {
        if { $index2 >= 0 } {
            set back [ string range $tmp $index end ]
            #--- fill the middle with "..."
            set trimpath "$front...$back"
        } else {
            set trimpath "$front..."
        }
    }
}


