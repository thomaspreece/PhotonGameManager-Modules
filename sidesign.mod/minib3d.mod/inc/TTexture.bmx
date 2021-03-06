Type TPixmapTexture Extends TTexture
	Field MipPixmaps:TPixmap[]
	
	Function LoadTexturePixmap:TPixmapTexture(file$ , flags:Int = 1 , tex:TPixmapTexture = Null)
		
		If flags & 128 Then RuntimeError "Not Implimented"
		If tex = Null Then tex:TPixmapTexture = New TPixmapTexture
		
		If FileType(file$) = 0 Then Return Null
		
		tex.file$=file$
		tex.file_abs$=FileAbs$(file$)
		
		tex.flags=flags
		tex.FilterFlags()
	?Threaded	
		LockMutex(Mutex_tex_list)
	?	
		Local old_tex:TTexture
		old_tex = tex.TexInList()
	?Threaded		
		UnlockMutex(Mutex_tex_list)
	?
		
		If old_tex <> Null
			Return Null
		EndIf				
		
		tex.pixmap = LoadPixmap(file$)
		
		tex.pixWidth = tex.pixmap.width
		tex.pixHeight = tex.pixmap.height

		Local alpha_present:Int=False
		If tex.pixmap.format=PF_RGBA8888 Or tex.pixmap.format=PF_BGRA8888 Or tex.pixmap.format=PF_A8 Then alpha_present=True

		' convert pixmap to appropriate format
		If tex.pixmap.format<>PF_RGBA8888
			tex.pixmap=tex.pixmap.Convert(PF_RGBA8888)
		EndIf
		
		' if alpha flag is true and pixmap doesn't contain alpha info, apply alpha based on color values
		If tex.flags&2 And alpha_present=False
			tex.pixmap=ApplyAlpha(tex.pixmap)
		EndIf		

		' if mask flag is true, mask pixmap
		If tex.flags&4
			tex.pixmap=MaskPixmap(tex.pixmap,0,0,0)
		EndIf
	
		tex.pixmap = AdjustPixmap(tex.pixmap)
		tex.width = tex.pixmap.width
		tex.height = tex.pixmap.height
		Local width:Int = tex.pixmap.width
		Local height:Int = tex.pixmap.height
		
		Local MipPixmaps:TList = CreateList()
		'Local MipParams:TList = CreateList()
		
		Local Pixmap:TPixmap = tex.pixmap
		ListAddLast(MipPixmaps , Pixmap)
		
		If tex.flags & 8 Then
			Repeat
				If width=1 And height=1 Exit
				If width>1 width:/2
				If height>1 height:/2
				
				Pixmap = ResizePixmap(tex.pixmap,width,height)
				ListAddLast(MipPixmaps , Pixmap)
			Forever
		EndIf

		tex.MipPixmaps = TPixmap[](ListToArray(MipPixmaps) )
		
		ClearList(MipPixmaps)
		MipPixmaps = Null 
		
		Return tex			
	End Function	

End Type



Type TTexture
	Global tex_list:TList = CreateList()
	Global UsedSpace:Int = 0	
?Threaded
	Global Mutex_tex_list:TMutex = CreateMutex()
	Global Mutex_UsedSpace:TMutex = CreateMutex()
?

	Field file$,flags:Int,blend:Int=2,coords:Int,u_scale#=1.0,v_scale#=1.0,u_pos#,v_pos#,angle#
	Field file_abs$,width:Int,height:Int ' returned by Name/Width/Height commands
	Field pixmap:TPixmap
	Field gltex:Int[1]
	Field cube_pixmap:TPixmap[7]
	Field no_frames:Int=1
	Field no_mipmaps:Int
	Field cube_face:Int = 0 , cube_mode:Int = 1
	Field pixWidth:Int, pixHeight:Int

	Method New()
	
		If LOG_NEW
			DebugLog "New TTexture"
		EndIf
	
	End Method
	
	Method Delete()
	
		If LOG_DEL
			DebugLog "Del TTexture"
		EndIf
	
	End Method

	Method FreeTexture() 'SMALLFIXES New function from http://www.blitzbasic.com/Community/posts.php?topic=88263#1002039
	?Threaded	
		LockMutex(Mutex_tex_list)
	?
		ListRemove(tex_list , Self)
		pixmap=Null
		cube_pixmap=Null
	?Threaded	
		LockMutex(Mutex_UsedSpace)
	?
		UsedSpace = UsedSpace - (5*3*width*height)/8
	?Threaded			
		UnlockMutex(Mutex_UsedSpace)
	?
		
		
		For Local name:Int = EachIn gltex
			glDeleteTextures 1, Varptr name
		Next
		gltex = Null
	?Threaded	
		UnlockMutex(Mutex_tex_list)	
	?
	End Method
	
	Function CreateTexture:TTexture(width:Int,height:Int,flags:Int=1,frames:Int=1,tex:TTexture=Null)
		RuntimeError "Not Implimented"
	End Function

	Function LoadTextureFromPixmap:TTexture(texPixmap:TPixmapTexture)
		If texPixmap = Null Then Return Null
		
		Local tex:TTexture = TTexture(texPixmap)
		
		Local old_tex:TTexture
	?Threaded	
		LockMutex(Mutex_tex_list)
	?
		old_tex=tex.TexInList()
		If old_tex <> Null And old_tex <> tex
	?Threaded		
			UnlockMutex(Mutex_tex_list)	
	?
			Return Null 
		EndIf
	?Threaded	
		UnlockMutex(Mutex_tex_list)
	?
		
		'Local pixmap:TPixmap
		
		Local width:Int=tex.width
		Local height:Int=tex.height

		tex.no_frames=1
		tex.gltex=tex.gltex[..1]

		Local name:Int
		glGenTextures 1,Varptr name
		glBindTexture GL_TEXTURE_2D,name

		Local mipmap:Int
		If tex.flags&8 Then mipmap=True
		Local mip_level:Int=0
	?Threaded	
		LockMutex(Mutex_UsedSpace)
	?
		Repeat
			'pixmap=texPixmap.MipPixmaps[mip_level]
			glPixelStorei GL_UNPACK_ROW_LENGTH,texPixmap.MipPixmaps[mip_level].pitch/BytesPerPixel[texPixmap.MipPixmaps[mip_level].format]
			glTexImage2D GL_TEXTURE_2D,mip_level,GL_RGB5,width,height,0,GL_RGBA,GL_UNSIGNED_BYTE,texPixmap.MipPixmaps[mip_level].pixels
			
			UsedSpace = UsedSpace + (5*3*width*height)/8
			If Not mipmap Then Exit
			If width=1 And height=1 Exit
			If width>1 width:/2
			If height>1 height:/2

			
			mip_level:+1
		Forever
	?Threaded	
		UnlockMutex(Mutex_UsedSpace)
	?
		tex.no_mipmaps=mip_level

		tex.gltex[0] = name
		
		texPixmap.MipPixmaps = Null
		texPixmap.pixmap = Null
		tex.pixmap = Null
	?Threaded	
		LockMutex(Mutex_tex_list)
	?
		ListAddLast(tex_list , tex)	
	?Threaded	
		UnlockMutex(Mutex_tex_list)	
	?
		Return tex
		
	End Function
	
	Function LoadPreloadedTexture:TTexture(file$ , flags:Int = 1)
		If flags&128 Then RuntimeError "Not Implimented"
	
		Local tex:TTexture=New TTexture
		
		tex.file$=file$
		tex.file_abs$=FileAbs$(file$)
		
		' set tex.flags before TexInList
		tex.flags=flags
		tex.FilterFlags()
	?Threaded	
		LockMutex(Mutex_tex_list)
	?	
		Local old_tex:TTexture
		old_tex = tex.TexInList()
	?Threaded	
		UnlockMutex(Mutex_tex_list)
	?
		If old_tex <> Null And old_tex <> tex
			Return old_tex
		Else
			Return Null
		EndIf

	End Function

	Function LoadTexture:TTexture(file$,flags:Int=1,tex:TTexture=Null)
			Local ATex:TTexture
			Local ATexPix:TPixmapTexture
			ATexPix = LoadTexturePixmap(file$,flags)
			ATex = LoadTextureFromPixmap(ATexPix)
			ATex = LoadPreloadedTexture(file$,flags)
			Return ATex
	End Function

	Function LoadAnimTexture:TTexture(file$,flags:Int,frame_width:Int,frame_height:Int,first_frame:Int,frame_count:Int,tex:TTexture=Null)
			RuntimeError "Not Implimented"
	End Function	

	Function CreateCubeMapTexture:TTexture(width:Int,height:Int,flags:Int,tex:TTexture=Null)
		RuntimeError "Not Implimented"
	End Function

	Function LoadCubeMapTexture:TTexture(file$,flags:Int=1,tex:TTexture=Null)
		RuntimeError "Not Implimented"
	End Function

	Method TextureBlend(blend_no:Int)
		
		blend=blend_no
		
	End Method
	
	Method TextureCoords(coords_no:Int)
	
		coords=coords_no
	
	End Method
	
	Method ScaleTexture(u_s#,v_s#)
	
		u_scale#=1.0/u_s#
		v_scale#=1.0/v_s#
	
	End Method
	
	Method PositionTexture(u_p#,v_p#)
	
		u_pos#=-u_p#
		v_pos#=-v_p#
	
	End Method
	
	Method RotateTexture(ang#)
	
		angle#=ang#
	
	End Method
	
	Method TextureWidth:Int()
	
		Return width
	
	End Method
	
	Method TextureHeight:Int()
	
		Return height
	
	End Method
	
	Method TextureName$()
	
		Return file_abs$
	
	End Method
	
	Function GetBrushTexture:TTexture(brush:TBrush,index:Int=0)
	
		Return brush.tex[index]
	
	End Function
	
	Function ClearTextureFilters()
	
		ClearList TTextureFilter.filter_list
	
	End Function
	
	Function TextureFilter(match_text$,flags:Int)
	
		Local filter:TTextureFilter=New TTextureFilter
		filter.Text$=match_text$
		filter.flags=flags
		ListAddLast(TTextureFilter.filter_list,filter)
	
	End Function
	
	Method SetCubeFace(face:Int)
		cube_face=face
	End Method
	
	Method SetCubeMode(Mode:Int)
		cube_mode=Mode
	End Method
	
	Method BackBufferToTex(mipmap_no:Int=0,frame:Int=0)
	
		If flags&128=0 ' normal texture
	
			Local x:Int=0,y:Int=0
	
			glBindTexture GL_TEXTURE_2D,gltex[frame]
			glCopyTexImage2D(GL_TEXTURE_2D,mipmap_no,GL_RGBA8,x,TGlobal.height-y-height,width,height,0)
			
		Else ' cubemap texture

			Local x:Int=0,y:Int=0
	
			glBindTexture GL_TEXTURE_CUBE_MAP_EXT,gltex[0]
			Select cube_face
				Case 0 glCopyTexImage2D(GL_TEXTURE_CUBE_MAP_NEGATIVE_X,mipmap_no,GL_RGBA8,x,TGlobal.height-y-height,width,height,0)
				Case 1 glCopyTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_Z,mipmap_no,GL_RGBA8,x,TGlobal.height-y-height,width,height,0)
				Case 2 glCopyTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X,mipmap_no,GL_RGBA8,x,TGlobal.height-y-height,width,height,0)
				Case 3 glCopyTexImage2D(GL_TEXTURE_CUBE_MAP_NEGATIVE_Z,mipmap_no,GL_RGBA8,x,TGlobal.height-y-height,width,height,0)
				Case 4 glCopyTexImage2D(GL_TEXTURE_CUBE_MAP_NEGATIVE_Y,mipmap_no,GL_RGBA8,x,TGlobal.height-y-height,width,height,0)
				Case 5 glCopyTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_Y,mipmap_no,GL_RGBA8,x,TGlobal.height-y-height,width,height,0)
			End Select
		
		EndIf

	End Method
		
	Method CountMipmaps:Int()
		Return no_mipmaps
	End Method
	
	Method MipmapWidth:Int(mipmap_no:Int)
		If mipmap_no>=0 And mipmap_no<=no_mipmaps
			Return width/(mipmap_no+1)
		Else
			Return 0
		EndIf
	End Method
	
	Method MipmapHeight:Int(mipmap_no:Int)
		If mipmap_no>=0 And mipmap_no<=no_mipmaps
			Return height/(mipmap_no+1)
		Else
			Return 0
		EndIf
	End Method
	
	
	Function FileFind%(file$ Var) 'SMALLFIXES, replaced function to alow Incbin and Zipstream (from http://blitzmax.com/Community/posts.php?topic=88901#1009408 ) 
		Local TS:TStream = OpenFile(file$,True,False)
		If Not TS Then
			Repeat
				file$=Right$(file$,(Len(file$)-Instr(file$,"\",1)))
			Until Instr(file$,"\",1)=0
			Repeat
				file$=Right$(file$,(Len(file$)-Instr(file$,"/",1)))
			Until Instr(file$,"/",1)=0
			TS = OpenStream(file$,True,False)
			If Not TS Then
				DebugLog "ERROR: Cannot find texture: "+file$
				Return False
			Else
			    CloseStream(TS)
                            TS=Null
			EndIf
		Else
			CloseStream TS
			TS=Null	
		EndIf
		Return True
	End Function
	
	
	Rem
	' Internal - not recommended for general use	
	Function FileFind:Int(file$ Var)
	
		If FileType(file$)=0
			Repeat
				file$=Right$(file$,(Len(file$)-Instr(file$,"\",1)))
			Until Instr(file$,"\",1)=0
			Repeat
				file$=Right$(file$,(Len(file$)-Instr(file$,"/",1)))
			Until Instr(file$,"/",1)=0
			If FileType(file$)=0
				DebugLog "ERROR: Cannot find texture: "+file$
				Return False
			EndIf
		EndIf
		
		Return True
		
	End Function
	EndRem
	
	Function FileAbs$(file$)
	
		Local file_abs$
	
		If Instr(file$,":")=False
			file_abs$=CurrentDir$()+"/"+file$
		Else
			file_abs$=file$
		EndIf
		file_abs$=Replace$(file_abs$,"\","/")
		
		Return file_abs$
	
	End Function
		
	Method TexInList:TTexture()

		' check if tex already exists in list and if so return it

		For Local tex:TTexture=EachIn tex_list
			If file$=tex.file$ And flags=tex.flags And blend=tex.blend
				If u_scale#=tex.u_scale# And v_scale#=tex.v_scale# And u_pos#=tex.u_pos# And v_pos#=tex.v_pos# And angle#=tex.angle#
					Return tex
				EndIf
			EndIf
		Next
	
		Return Null
	
	End Method
	
	Method FilterFlags()
	
		' combine specifieds flag with texture filter flags
		For Local filter:TTextureFilter=EachIn TTextureFilter.filter_list
			If Instr(file$,filter.Text$) Then flags=flags|filter.flags
		Next
	
	End Method
		
	Function AdjustPixmap:TPixmap(pixmap:TPixmap)
	
		' adjust width and height size to next biggest power of 2 size
		Local width:Int=Pow2Size(pixmap.width)
		Local height:Int=Pow2Size(pixmap.height)

		' ***note*** commented out as it fails on some cards
		Rem
		' check that width and height size are valid (not too big)
		Repeat
			Local t
			glTexImage2D GL_PROXY_TEXTURE_2D,0,4,width,height,0,GL_RGBA,GL_UNSIGNED_BYTE,Null
			glGetTexLevelParameteriv GL_PROXY_TEXTURE_2D,0,GL_TEXTURE_WIDTH,Varptr t
			If t Exit
			If width=1 And height=1 RuntimeError "Unable to calculate tex size"
			If width>1 width:/2
			If height>1 height:/2
		Forever
		End Rem

		' if width or height have changed then resize pixmap
		If width<>pixmap.width Or height<>pixmap.height
			pixmap=ResizePixmap(pixmap,width,height)
		EndIf
		
		' return pixmap
		Return pixmap
		
	End Function
	
	Function Pow2Size:Int( n:Int )
		Local t:Int=1
		While t<n
			t:*2
		Wend
		Return t
	End Function

	' applys alpha to a pixmap based on average of colour values
	Function ApplyAlpha:TPixmap( pixmap:TPixmap ) NoDebug
	
		Local tmp:TPixmap=pixmap
		If tmp.format<>PF_RGBA8888 tmp=tmp.Convert( PF_RGBA8888 )
		
		Local out:TPixmap=CreatePixmap( tmp.width,tmp.height,PF_RGBA8888 )
		
		For Local y:Int=0 Until pixmap.height
			Local t:Byte Ptr=tmp.PixelPtr( 0,y )
			Local o:Byte Ptr=out.PixelPtr( 0,y )
			For Local x:Int=0 Until pixmap.width

				o[0]=t[0]
				o[1]=t[1]
				o[2]=t[2]
				o[3]=(o[0]+o[1]+o[2])/3.0

				t:+4
				o:+4
			Next
		Next
		Return out
	End Function

End Type

Type TTextureFilter

	Global filter_list:TList=CreateList()

	Field Text$
	Field flags:Int
	
End Type
