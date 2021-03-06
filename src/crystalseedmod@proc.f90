! Copyright (c) 2007-2018 Alberto Otero de la Roza <aoterodelaroza@gmail.com>,
! Ángel Martín Pendás <angel@fluor.quimica.uniovi.es> and Víctor Luaña
! <victor@fluor.quimica.uniovi.es>. 
!
! critic2 is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or (at
! your option) any later version.
! 
! critic2 is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
! 
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

submodule (crystalseedmod) proc
  implicit none

  !xx! private subroutines
  ! subroutine read_all_cif(nseed,seed,file,mol,errmsg)
  ! subroutine read_all_qeout(nseed,seed,file,mol,istruct,errmsg)
  ! subroutine read_all_crystalout(nseed,seed,file,mol,errmsg)
  ! subroutine read_all_xyz(nseed,seed,file,errmsg)
  ! subroutine read_all_log(nseed,seed,file,errmsg)
  ! subroutine read_cif_items(seed,mol,errmsg)
  ! function is_espresso(file)
  ! subroutine qe_latgen(ibrav,celldm,a1,a2,a3,errmsg)
  ! subroutine spgs_wrap(seed,spg,usespgr)

contains

  !> Parse a crystal environment
  module subroutine parse_crystal_env(seed,lu,oksyn)
    use global, only: eval_next, dunit0, iunit, iunit_isdef, iunit_bohr
    use arithmetic, only: isvariable, eval, setvariable
    use tools_math, only: matinv
    use tools_io, only: uin, getline, ucopy, lgetword, equal, ferror, faterr,&
       getword, lower, isinteger, string, nameguess, zatguess, equali
    use param, only: bohrtoa
    use types, only: realloc

    class(crystalseed), intent(inout) :: seed !< Crystal seed output
    integer, intent(in) :: lu !< Logical unit for input
    logical, intent(out) :: oksyn !< Was there a syntax error?

    character(len=:), allocatable :: word, aux, aexp, line, name
    character*255, allocatable :: sline(:)
    integer :: i, j, k, lp, nsline, idx, luout, iat, lp2, iunit0, it
    real*8 :: rmat(3,3), scal, ascal, x(3), xn(3)
    logical :: ok, goodspg, useit
    character*(1), parameter :: ico(3) = (/"x","y","z"/)
    logical :: icodef(3), iok, isset
    real*8 :: icoval(3)

    if (iunit_isdef) then
       iunit0 = iunit_bohr
    else
       iunit0 = iunit
    end if

    oksyn = .false.
    goodspg = .false.
    seed%nat = 0
    seed%nspc = 0
    seed%useabr = 0
    nsline = 0
    if (lu == uin) then
       luout = ucopy
    else
       luout = -1
    endif
    allocate(seed%x(3,10),seed%is(10),seed%spc(2))
    do while (getline(lu,line,ucopy=luout))
       lp = 1
       word = lgetword(line,lp)
       if (equal (word,'cell')) then
          ! cell <a> <b> <c> <alpha> <beta> <gamma>
          ok = eval_next(seed%aa(1),line,lp)
          ok = ok .and. eval_next(seed%aa(2),line,lp)
          ok = ok .and. eval_next(seed%aa(3),line,lp)
          ok = ok .and. eval_next(seed%bb(1),line,lp)
          ok = ok .and. eval_next(seed%bb(2),line,lp)
          ok = ok .and. eval_next(seed%bb(3),line,lp)
          if (.not.ok) then
             call ferror("parse_crystal_env","Wrong CELL syntax",faterr,line,syntax=.true.)
             return
          endif
          isset = .false.
          word = lgetword(line,lp)
          if (equal(word,'angstrom').or.equal(word,'ang')) then
             isset = .true.
             seed%aa = seed%aa / bohrtoa
          elseif (equal(word,'bohr').or.equal(word,'au')) then
             isset = .true.
          elseif (len_trim(word) > 0) then
             call ferror('parse_crystal_env','Unknown extra keyword in CELL',faterr,line,syntax=.true.)
             return
          endif
          if (.not.isset) then
             seed%aa = seed%aa / dunit0(iunit0)
          end if
          seed%useabr = 1

          ! cartesian <scale> .. endcartesian
       else if (equal (word,'cartesian')) then
          ok = eval_next(scal,line,lp)
          if (.not.ok) scal = 1d0
          ascal = 1d0/dunit0(iunit)
          aux = getword(line,lp)
          if (len_trim(aux) > 0) then
             call ferror('parse_crystal_env','Unknown extra keyword in CARTESIAN',faterr,line,syntax=.true.)
             return
          end if

          i = 0
          rmat = 0d0
          isset = .false.
          do while(.true.)
             lp = 1
             ok = getline(lu,line,ucopy=luout)
             word = lgetword(line,lp)
             if (equal(word,'angstrom') .or.equal(word,'ang')) then
                ! angstrom/ang
                ascal = 1d0/bohrtoa
                isset = .true.
             else if (equal(word,'bohr') .or.equal(word,'au')) then
                ! bohr/au
                ascal = 1d0
                isset = .true.
             else if (equal(word,'end').or.equal(word,'endcartesian')) then
                ! end/endcartesian
                aux = getword(line,lp)
                if (len_trim(aux) > 0) then
                   call ferror('parse_crystal_env','Unknown extra keyword in CARTESIAN',faterr,line,syntax=.true.)
                   return
                end if
                exit
             else
                ! matrix row
                i = i + 1
                if (i > 3) then
                   ok = .false.
                else
                   lp = 1
                   ok = ok .and. eval_next(rmat(i,1),line,lp)
                   ok = ok .and. eval_next(rmat(i,2),line,lp)
                   ok = ok .and. eval_next(rmat(i,3),line,lp)
                end if
             end if
             if (.not.ok) then
                call ferror('parse_crystal_env','Bad CARTESIAN environment',faterr,line,syntax=.true.)
                return
             end if
             aux = getword(line,lp)
             if (len_trim(aux) > 0) then
                call ferror('parse_crystal_env','Unknown extra keyword in CARTESIAN',faterr,line,syntax=.true.)
                return
             end if
          end do
          if (.not.isset) then
             ascal = 1d0 / dunit0(iunit0)
          end if
          seed%m_x2c = transpose(rmat) * scal * ascal
          rmat = matinv(seed%m_x2c)
          seed%useabr = 2

       else if (equal(word,'spg').or.equal(word,'spgr')) then
          ! spg <spg>
          useit = equal(word,'spgr')
          word = line(lp:)
          call spgs_wrap(seed,word,useit)
          goodspg = (seed%havesym > 0)

       else if (equal(word,'symm')) then
          ! symm <line>
          if (.not.allocated(sline)) allocate(sline(10))
          nsline = nsline + 1
          if (nsline > size(sline)) call realloc(sline,2*size(sline))
          sline(nsline) = lower(adjustl(line(lp:)))

       else if (equal(word,'endcrystal') .or. equal(word,'end')) then
          ! endcrystal/end
          exit
       else
          ! keyword not found, must be an atom. The syntax:
          !    neq <x> <y> <z> <atom> ...
          !    <atom> <x> <y> <z> ...
          !    <atnumber> <x> <y> <z> ...
          ! are acceptable
          seed%nat = seed%nat + 1
          if (seed%nat > size(seed%x,2)) then
             call realloc(seed%x,3,2*seed%nat)
             call realloc(seed%is,2*seed%nat)
          end if

          if (.not.equal(word,'neq')) then
             ! try to read four fields from the input
             lp2 = 1
             ok = isinteger(iat,line,lp2)
             ok = ok .and. eval_next(seed%x(1,seed%nat),line,lp2)
             ok = ok .and. eval_next(seed%x(2,seed%nat),line,lp2)
             ok = ok .and. eval_next(seed%x(3,seed%nat),line,lp2)
             if (.not.ok) then
                ! then it must be <atom> <x> <y> <z>
                ok = eval_next(seed%x(1,seed%nat),line,lp)
                ok = ok .and. eval_next(seed%x(2,seed%nat),line,lp)
                ok = ok .and. eval_next(seed%x(3,seed%nat),line,lp)
                if (.not.ok) then
                   call ferror("parse_crystal_env","Wrong atomic input syntax",faterr,line,syntax=.true.)
                   return
                end if
                name = string(word)
             else
                lp = lp2
                name = nameguess(iat,.true.)
             end if
          else
             ok = eval_next(seed%x(1,seed%nat),line,lp)
             ok = ok .and. eval_next(seed%x(2,seed%nat),line,lp)
             ok = ok .and. eval_next(seed%x(3,seed%nat),line,lp)
             if (.not.ok) then
                call ferror("parse_crystal_env","Wrong NEQ syntax",faterr,line,syntax=.true.)
                return
             end if
             name = trim(getword(line,lp))
          end if

          it = 0
          do i = 1, seed%nspc
             if (equali(seed%spc(i)%name,name)) then
                it = i
                exit
             end if
          end do
          if (it == 0) then
             seed%nspc = seed%nspc + 1
             if (seed%nspc > size(seed%spc,1)) &
                call realloc(seed%spc,2*seed%nspc)
             it = seed%nspc
             seed%spc(it)%name = name
             seed%spc(it)%z = zatguess(name)
             if (seed%spc(it)%z < 0) then
                call ferror('parse_crystal_env','Unknown atomic symbol in NEQ',faterr,line,syntax=.true.)
                return
             end if
             seed%spc(it)%qat = 0d0
          end if
          seed%is(seed%nat) = it

          do while (.true.)
             word = lgetword(line,lp)
             if (equal(word,'ang') .or. equal(word,'angstrom')) then
                if (seed%useabr /= 2) then
                   call ferror('parse_crystal_env','Need CARTESIAN for angstrom coordinates',faterr,line,syntax=.true.)
                   return
                end if
                seed%x(:,seed%nat) = matmul(rmat,seed%x(:,seed%nat) / bohrtoa)
             else if (equal(word,'bohr') .or. equal(word,'au')) then
                if (seed%useabr /= 2) then
                   call ferror('parse_crystal_env','Need CARTESIAN for bohr coordinates',faterr,line,syntax=.true.)
                   return
                end if
                seed%x(:,seed%nat) = matmul(rmat,seed%x(:,seed%nat))
             else if (len_trim(word) > 0) then
                call ferror('parse_crystal_env','Unknown keyword in NEQ',faterr,line,syntax=.true.)
                return
             else
                exit
             end if
          end do
       end if
    end do
    aux = getword(line,lp)
    if (len_trim(aux) > 0) then
       call ferror('parse_crystal_env','Unknown extra keyword in ENDCRYSTAL',faterr,line,syntax=.true.)
       return
    end if
    if (seed%nat == 0) then
       call ferror('parse_crystal_env','No atoms in input',faterr,syntax=.true.)
       return
    end if
    if (seed%useabr == 0) then
       call ferror('parse_crystal_env','No cell information given',faterr,syntax=.true.)
       return
    end if

    ! symm transformation
    if (nsline > 0 .and. allocated(sline)) then
       ! save the old x,y,z variables if they are defined
       do k = 1, 3
          icodef(k) = isvariable(ico(k),icoval(k))
       end do

       do i = 1, nsline ! run over symm lines
          do j = 1, seed%nat ! run over atoms
             line = trim(adjustl(sline(i)))
             xn = seed%x(:,j) - floor(seed%x(:,j))
             ! push the atom coordinates into x,y,z variables
             do k = 1, 3 
                call setvariable(ico(k),seed%x(k,j))
             end do

             ! parse the three fields in the arithmetic expression 
             do k = 1, 3
                if (k < 3) then
                   idx = index(line,",")
                   if (idx == 0) then
                      call ferror('parse_crystal_env','error reading symmetry operation',faterr,line,syntax=.true.)
                      return
                   end if
                   aexp = line(1:idx-1)
                   aux = adjustl(line(idx+1:))
                   line = aux
                else
                   aexp = line
                end if
                x(k) = eval(aexp,.true.,iok)
             end do
             x = x - floor(x)

             ! check if this atom already exists
             ok = .true.
             do k = 1, seed%nat
                if (all(abs(x - xn) < 1d-5)) then
                   ok = .false.
                   exit
                endif
             end do

             ! add this atom to the list
             if (ok) then
                seed%nat = seed%nat + 1
                if (seed%nat > size(seed%x,2)) then
                   call realloc(seed%x,3,2*seed%nat)
                   call realloc(seed%is,2*seed%nat)
                end if
                seed%is(seed%nat) = seed%is(j)
                seed%x(:,seed%nat) = x
             endif
          end do
       end do
       deallocate(sline)

       ! re-set the previous values of x, y, z
       do k = 1, 3
          if (icodef(k)) call setvariable(ico(k),icoval(k))
       end do
    end if
    call realloc(seed%x,3,seed%nat)
    call realloc(seed%is,seed%nat)
    call realloc(seed%spc,seed%nspc)

    ! symmetry
    if (goodspg) then
       seed%havesym = 1
       seed%findsym = 0
       seed%checkrepeats = 0
    else
       seed%havesym = 0
       seed%findsym = -1
    end if
    oksyn = .true.

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = .false.
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = "<input>"
    seed%name = "<input>"

  end subroutine parse_crystal_env

  !> Parse a molecule environment
  module subroutine parse_molecule_env(seed,lu,oksyn)
    use global, only: rborder_def, eval_next, dunit0, iunit, iunit_ang, iunit_isdef
    use tools_io, only: uin, ucopy, getline, lgetword, equal, ferror, faterr,&
       string, isinteger, nameguess, getword, zatguess, equali
    use param, only: bohrtoa
    use types, only: realloc

    class(crystalseed), intent(inout) :: seed !< Crystal seed output
    integer, intent(in) :: lu !< Logical unit for input
    logical, intent(out) :: oksyn !< Was there a syntax error?

    character(len=:), allocatable :: word, aux, line, name
    integer :: lp, lp2, luout, iat, iunit0, it, i
    real*8 :: rborder
    logical :: ok, docube, isset

    if (iunit_isdef) then
       iunit0 = iunit_ang
    else
       iunit0 = iunit
    end if

    ok = .false.
    docube = .false.
    rborder = rborder_def 
    seed%nat = 0
    seed%nspc = 0
    allocate(seed%x(3,10),seed%is(10),seed%spc(2))
    if (lu == uin) then
       luout = ucopy
    else
       luout = -1
    endif
    do while (getline(lu,line,ucopy=luout))
       lp = 1
       word = lgetword(line,lp)

       if (equal(word,'cube').or.equal(word,'cubic')) then
          ! cube
          docube = .true.
          word = lgetword(line,lp)
          ok = check_no_extra_word()
          if (.not.ok) return

       else if (equal(word,'border')) then
          ! border [border.r]
          ok = eval_next(rborder,line,lp)
          if (.not.ok) then
             call ferror('parse_molecule_input','Wrong syntax in BORDER',faterr,line,syntax=.true.)
             return
          end if
          ok = check_no_extra_word()
          if (.not.ok) return

       else if (equal(word,'endmolecule') .or. equal(word,'end')) then
          ! endmolecule/end
          exit
       else
          ! keyword not found, must be an atom. The syntax:
          !    neq <x> <y> <z> <atom> ...
          !    <atom> <x> <y> <z> ...
          !    <atnumber> <x> <y> <z> ...
          ! are acceptable
          seed%nat = seed%nat + 1
          if (seed%nat > size(seed%x,2)) then
             call realloc(seed%x,3,2*seed%nat)
             call realloc(seed%is,2*seed%nat)
          end if

          if (.not.equal(word,'neq')) then
             ! try to read four fields from the input
             lp2 = 1
             ok = isinteger(iat,line,lp2)
             ok = ok .and. eval_next(seed%x(1,seed%nat),line,lp2)
             ok = ok .and. eval_next(seed%x(2,seed%nat),line,lp2)
             ok = ok .and. eval_next(seed%x(3,seed%nat),line,lp2)
             if (.not.ok) then
                ! then it must be <atom> <x> <y> <z>
                ok = eval_next(seed%x(1,seed%nat),line,lp)
                ok = ok .and. eval_next(seed%x(2,seed%nat),line,lp)
                ok = ok .and. eval_next(seed%x(3,seed%nat),line,lp)
                if (.not.ok) then
                   call ferror("parse_molecule_env","Wrong atomic input syntax",faterr,line,syntax=.true.)
                   return
                end if
                name = string(word)
             else
                lp = lp2
                name = nameguess(iat,.true.)
             endif
          else
             ok = eval_next(seed%x(1,seed%nat),line,lp)
             ok = ok .and. eval_next(seed%x(2,seed%nat),line,lp)
             ok = ok .and. eval_next(seed%x(3,seed%nat),line,lp)
             if (.not.ok) then
                call ferror("parse_molecule_env","Wrong NEQ syntax",faterr,line,syntax=.true.)
                return
             end if
             name = trim(getword(line,lp))
          endif

          it = 0
          do i = 1, seed%nspc
             if (equali(seed%spc(i)%name,name)) then
                it = i
                exit
             end if
          end do
          if (it == 0) then
             seed%nspc = seed%nspc + 1
             if (seed%nspc > size(seed%spc,1)) &
                call realloc(seed%spc,2*seed%nspc)
             it = seed%nspc
             seed%spc(it)%name = name
             seed%spc(it)%z = zatguess(name)
             if (seed%spc(it)%z < 0) then
                call ferror('parse_molecule_env','Unknown atomic symbol in NEQ',faterr,line,syntax=.true.)
                return
             end if
             seed%spc(it)%qat = 0d0
          end if
          seed%is(seed%nat) = it

          isset = .false.
          do while (.true.)
             word = lgetword(line,lp)
             if (equal(word,'ang') .or. equal(word,'angstrom')) then
                isset = .true.
                seed%x(:,seed%nat) = seed%x(:,seed%nat) / bohrtoa
             else if (equal(word,'bohr') .or. equal(word,'au')) then
                isset = .true.
             else if (len_trim(word) > 0) then
                call ferror('parse_molecule_input','Unknown extra keyword in atomic input',faterr,line,syntax=.true.)
                return
             else
                exit
             end if
          end do
          if (.not.isset) then
             seed%x(:,seed%nat) = seed%x(:,seed%nat) / dunit0(iunit0)
          end if
       endif
    end do
    aux = getword(line,lp)
    if (len_trim(aux) > 0) then
       call ferror('parse_molecule_input','Unknown extra keyword in ENDMOLECULE',faterr,line,syntax=.true.)
       return
    end if
    if (seed%nat == 0) then
       call ferror('parse_molecule_input','No atoms in input',faterr,syntax=.true.)
       return
    end if
    call realloc(seed%x,3,seed%nat)
    call realloc(seed%is,seed%nat)
    call realloc(seed%spc,seed%nspc)
    oksyn = .true.
    seed%useabr = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = .true.
    seed%cubic = docube
    seed%border = rborder
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = "<input>"
    seed%name = "<input>"

  contains
    function check_no_extra_word()
      character(len=:), allocatable :: aux2
      logical :: check_no_extra_word
      aux2 = getword(line,lp)
      if (len_trim(aux2) > 0) then
         call ferror('critic','Unknown extra keyword',faterr,line,syntax=.true.)
         check_no_extra_word = .false.
      else
         check_no_extra_word = .true.
      end if
    end function check_no_extra_word

  end subroutine parse_molecule_env

  !> Read a structure from the critic2 structure library
  module subroutine read_library(seed,line,mol,oksyn)
    use global, only: mlib_file, clib_file
    use tools_io, only: lgetword, ferror, faterr, uout, fopen_read, getline,&
       equal, getword, fclose

    class(crystalseed), intent(inout) :: seed !< Crystal seed result
    character*(*), intent(in) :: line !< Library entry
    logical, intent(in) :: mol !< Is this a molecule?
    logical, intent(out) :: oksyn !< Did this have a syntax error?

    character(len=:), allocatable :: word, l2, stru, aux, libfile
    logical :: lchk, found, ok
    integer :: lu, lp, lpo

    ! read the structure
    oksyn = .false.
    lpo = 1
    stru = lgetword(line,lpo)
    if (len_trim(stru) < 1) then
       call ferror("read_library","structure label missing in CRYSTAL/MOLECULE LIBRARY",faterr,line,syntax=.true.)
       return
    endif

    if (mol) then
       libfile = mlib_file
    else
       libfile = clib_file
    endif

    ! open the library file
    inquire(file=libfile,exist=lchk)
    if (.not.lchk) then
       write (uout,'("(!) Library file:"/8X,A)') trim(libfile)
       call ferror("read_library","library file not found!",faterr,syntax=.true.)
       return
    endif
    lu = fopen_read(libfile,abspath0=.true.)

    ! find the block
    found = .false.
    main: do while (getline(lu,l2))
       lp = 1
       word = lgetword(l2,lp)
       if (equal(word,'structure')) then
          do while(len_trim(word) > 0)
             word = lgetword(l2,lp)
             if (equal(word,stru)) then
                found = .true.
                exit main
             endif
          end do
       endif
    end do main
    if (.not.found) then
       write (uout,'("(!) Structure not found in file:"/8X,A)') trim(libfile)
       call ferror("read_library","structure not found in library!",faterr,syntax=.true.)
       call fclose(lu)
       return
    end if

    ! read the crystal/molecule environment inside
    ok = getline(lu,l2)
    if (mol) then
       call seed%parse_molecule_env(lu,ok)
       seed%file = "molecular library (" // trim(line) // ")"
       seed%name = "molecular library (" // trim(line) // ")"
    else
       call seed%parse_crystal_env(lu,ok)
       seed%file = "crystal library (" // trim(line) // ")"
       seed%name = "crystal library (" // trim(line) // ")"
    endif
    call fclose(lu)
    if (.not.ok) return

    ! make sure there's no more input
    aux = getword(line,lpo)
    if (len_trim(aux) > 0) then
       call ferror('read_library','Unknown extra keyword in CRYSTAL/MOLECULE LIBRARY',faterr,line,syntax=.true.)
       return
    end if
    oksyn = .true.

  end subroutine read_library

  !> Read the structure from a CIF file (uses ciftbx) and returns a 
  !> crystal seed.
  module subroutine read_cif(seed,file,dblock,mol,errmsg)
    use arithmetic, only: eval, isvariable, setvariable
    use global, only: critic_home
    use tools_io, only: falloc, uout, lower, zatguess, fdealloc, nameguess
    use param, only: dirsep
    use types, only: realloc

    class(crystalseed), intent(inout) :: seed !< Output crystal seed
    character*(*), intent(in) :: file !< Input file name
    character*(*), intent(in) :: dblock !< Data block
    logical, intent(in) :: mol !< Is this a molecule? 
    character(len=:), allocatable, intent(out) :: errmsg

    include 'ciftbx/ciftbx.cmv'
    include 'ciftbx/ciftbx.cmf'

    character(len=1024) :: dictfile
    logical :: fl
    integer :: ludum, luscr

    errmsg = ""
    ludum = falloc()
    luscr = falloc()
    fl = init_(ludum, uout, luscr, uout)
    if (.not.checkcifop()) goto 999

    ! open dictionary
    dictfile = trim(adjustl(critic_home)) // dirsep // "cif" // dirsep // 'cif_core.dic'
    fl = dict_(dictfile,'valid')
    if (.not.checkcifop()) goto 999
    if (.not.fl) then
       errmsg = "Dictionary file (cif_core.dic) not found. Check CRITIC_HOME"
       goto 999
    end if

    ! open cif file
    fl = ocif_(file)
    if (.not.checkcifop()) goto 999
    if (.not.fl) then
       errmsg = "CIF file not found: " // trim(file)
       goto 999
    end if

    ! move to the beginning of the data block
    fl = data_(dblock)
    if (.not.checkcifop()) goto 999
    if (.not.fl) then
       errmsg = "incorrect named data block: " // trim(dblock)
       goto 999
    end if

    ! read all the items
    call read_cif_items(seed,mol,errmsg)

999 continue

    ! clean up
    call purge_()
    call fdealloc(ludum)
    call fdealloc(luscr)

    ! rest of the seed information
    seed%file = file
    if (len_trim(dblock) > 0) then
       seed%name = trim(dblock)
    else
       seed%name = file
    end if

  contains
    function checkcifop()
      use tools_io, only: string
      logical :: checkcifop
      checkcifop = (cifelin_ == 0)
      if (checkcifop) then
         errmsg = ""
      else
         errmsg = trim(cifemsg_) // " (Line: " // string(cifelin_) // ")"
      end if
    end function checkcifop
  end subroutine read_cif

  !> Read the structure from a CIF file (uses ciftbx)
  module subroutine read_shelx(seed,file,mol,errmsg)
    use arithmetic, only: isvariable, eval, setvariable
    use tools_io, only: fopen_read, getline_raw, lgetword, equal, isreal, isinteger,&
       lower, zatguess, fclose
    use param, only: eyet, eye, bohrtoa
    use types, only: realloc
    class(crystalseed) :: seed !< Output crystal seed
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< Is this a molecule? 
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu, lp, ilat
    logical :: ok, iscent, iok, havecell
    character(len=1024) :: tok
    character(len=:), allocatable :: word, line, aux
    real*8 :: raux, rot0(3,4)
    integer :: i, j, idx, n
    integer :: iz
    real*8 :: xo, yo, zo
    logical :: iix, iiy, iiz
    integer :: lncv
    real*8, allocatable :: lcen(:,:)

    character*(1), parameter :: ico(3) = (/"x","y","z"/)

    ! file and seed name
    seed%file = file
    seed%name = file
    errmsg = ""
    iix = .false.
    iiy = .false.
    iiz = .false.

    ! initialize symmetry
    iscent = .false.
    seed%ncv = 1
    allocate(seed%cen(3,4))
    seed%cen = 0d0
    seed%neqv = 1
    allocate(seed%rotm(3,4,48))
    seed%rotm = 0d0
    seed%rotm(:,:,seed%neqv) = eyet
    havecell = .false.
    seed%nat = 0
    if (.not.allocated(seed%x)) allocate(seed%x(3,10))
    if (.not.allocated(seed%is)) allocate(seed%is(10))

    ! centering vectors may come in symm. If that happens, 
    ! replicate the atoms and let LATT determine the global 
    ! centering vectors
    lncv = 0
    allocate(lcen(3,1))
    lcen = 0d0

    ! save the old value of x, y, and z variables
    iix = isvariable("x",xo)
    iiy = isvariable("y",yo)
    iiz = isvariable("z",zo)

    lu = fopen_read(file)
    if (lu < 0) then
       errmsg = "Error opening file."
       if (iix) call setvariable("x",xo)
       if (iiy) call setvariable("y",yo)
       if (iiz) call setvariable("z",zo)
       return
    end if

    do while (.true.)
       ok = getline_local()
       if (.not.ok) exit
       lp = 1
       word = lgetword(line,lp)
       if (len_trim(word) > 4) word = word(1:4)
       if (equal(word,"titl")) then
          seed%name = trim(line(lp:))
       elseif (equal(word,"cell")) then
          ! read the cell parameters from the cell card
          ok = isreal(raux,line,lp)
          ok = ok .and. isreal(seed%aa(1),line,lp)
          ok = ok .and. isreal(seed%aa(2),line,lp)
          ok = ok .and. isreal(seed%aa(3),line,lp)
          ok = ok .and. isreal(seed%bb(1),line,lp)
          ok = ok .and. isreal(seed%bb(2),line,lp)
          ok = ok .and. isreal(seed%bb(3),line,lp)
          if (.not.ok) then
             errmsg = "Error reading CELL card."
             goto 999
          end if
          seed%aa = seed%aa / bohrtoa
          havecell = .true.
       elseif (equal(word,"latt")) then
          ! read the centering vectors from the latt card
          ok = isinteger(ilat,line,lp)
          if (.not.ok) then
             errmsg = "Error reading LATT card."
             goto 999
          end if
          select case(abs(ilat))
          case(1)
             ! P 
             seed%ncv=1
          case(2)
             ! I
             seed%ncv=2
             seed%cen(1,2)=0.5d0
             seed%cen(2,2)=0.5d0
             seed%cen(3,2)=0.5d0
          case(3)
             ! R obverse
             seed%ncv=3
             seed%cen(:,2) = (/2d0,1d0,1d0/) / 3d0
             seed%cen(:,3) = (/1d0,2d0,2d0/) / 3d0
          case(4)
             ! F
             seed%ncv=4
             seed%cen(1,2)=0.5d0
             seed%cen(2,2)=0.5d0
             seed%cen(2,3)=0.5d0
             seed%cen(3,3)=0.5d0
             seed%cen(1,4)=0.5d0
             seed%cen(3,4)=0.5d0
          case(5)
             ! A
             seed%ncv=2
             seed%cen(2,2)=0.5d0
             seed%cen(3,2)=0.5d0
          case(6)
             ! B
             seed%ncv=2
             seed%cen(1,2)=0.5d0
             seed%cen(3,2)=0.5d0
          case(7)
             ! C 
             seed%ncv=2
             seed%cen(1,2)=0.5d0
             seed%cen(2,2)=0.5d0
          case default
             errmsg = "Unknown LATT value."
             goto 999
          end select
          iscent = (ilat > 0)
       elseif (equal(word,"symm")) then
          ! symmetry operations from the symm card
          aux = lower(line(lp:)) // ","
          line = aux
          rot0 = 0d0
          do i = 1, 3
             idx = index(line,",")
             tok = lower(line(1:idx-1))
             aux = line(idx+1:)
             line = aux

             ! the translation component
             do j = 1, 3
                call setvariable(ico(j),0d0)
             end do
             rot0(i,4) = eval(tok,.true.,iok)

             ! the x-, y-, z- components
             do j = 1, 3
                call setvariable(ico(j),1d0)
                rot0(i,j) = eval(tok,.true.,iok) - rot0(i,4)
                call setvariable(ico(j),0d0)
             enddo
          end do

          if (all(abs(eye - rot0(1:3,1:3)) < 1d-12)) then
             ! a non-zero pure translation or the identity 
             if (all(abs(rot0(:,4)) < 1d-12)) then
                ! ignore the identity
             else
                ! must be a pure translation
                lncv = lncv + 1
                if (lncv > size(lcen,2)) &
                   call realloc(lcen,3,2*lncv)
                lcen(:,lncv) = rot0(:,4)
             endif
          else
             ! a rotation, with some pure translation in it
             ! check if I have this rotation matrix already
             ok = .true.
             do i = 1, seed%neqv
                if (all(abs(seed%rotm(:,:,i) - rot0(:,:)) < 1d-12)) then
                   ok = .false.
                   exit
                endif
             end do
             if (ok) then
                seed%neqv = seed%neqv + 1
                seed%rotm(:,:,seed%neqv) = rot0
             else
                errmsg = "Found repeated entry in SYMM."
                goto 999
             endif
          endif

       elseif (equal(word,"sfac")) then
          ! atomic types from the sfac card
          seed%nspc = 0
          allocate(seed%spc(2))
          do while (.true.)
             word = lgetword(line,lp)
             iz = zatguess(word)
             if (iz <= 0 .or. len_trim(word) < 1) exit
             seed%nspc = seed%nspc + 1
             if (seed%nspc > size(seed%spc,1)) call realloc(seed%spc,2*seed%nspc)
             seed%spc(seed%nspc)%z = iz
             seed%spc(seed%nspc)%name = trim(word)
          end do
          call realloc(seed%spc,seed%nspc)
       elseif (equal(word,"unit")) then
          ! ignore the unit card... some res files don't have it,
          ! and we can count the atoms in the list anyway

          ! ignore all the following cards
       elseif (equal(word,"abin").or.equal(word,"acta").or.equal(word,"afix").or.&
          equal(word,"anis").or.equal(word,"ansc").or.equal(word,"ansr").or.&
          equal(word,"basf").or.equal(word,"bind").or.equal(word,"bloc").or.&
          equal(word,"bond").or.equal(word,"bump").or.equal(word,"cgls").or.&
          equal(word,"chiv").or.equal(word,"conf").or.equal(word,"conn").or.&
          equal(word,"damp").or.equal(word,"dang").or.equal(word,"defs").or.&
          equal(word,"delu").or.equal(word,"dfix").or.equal(word,"disp").or.&
          equal(word,"eadp").or.equal(word,"eqiv").or.equal(word,"exti").or.&
          equal(word,"exyz").or.equal(word,"flat").or.equal(word,"fmap").or.&
          equal(word,"free").or.equal(word,"fvar").or.equal(word,"grid").or.&
          equal(word,"hfix").or.equal(word,"hklf").or.equal(word,"hope").or.&
          equal(word,"htab").or.&
          equal(word,"isor").or.equal(word,"laue").or.equal(word,"list").or.&
          equal(word,"l.s.").or.equal(word,"merg").or.equal(word,"mole").or.&
          equal(word,"more").or.&
          equal(word,"move").or.equal(word,"mpla").or.equal(word,"ncsy").or.&
          equal(word,"neut").or.equal(word,"omit").or.equal(word,"part").or.&
          equal(word,"plan").or.equal(word,"prig").or.equal(word,"rem").or.&
          equal(word,"resi").or.equal(word,"rigu").or.equal(word,"rtab").or.&
          equal(word,"sadi").or.equal(word,"same").or.equal(word,"shel").or.&
          equal(word,"simu").or.equal(word,"size").or.equal(word,"spec").or.&
          equal(word,"stir").or.equal(word,"sump").or.equal(word,"swat").or.&
          equal(word,"temp").or.equal(word,"time").or.&
          equal(word,"titl").or.equal(word,"twin").or.&
          equal(word,"twst").or.equal(word,"wght").or.equal(word,"wigl").or.&
          equal(word,"wpdb").or.equal(word,"xnpd").or.equal(word,"zerr")) then
          cycle

          ! also ignore the frag...fend blocks
       elseif (equal(word,"frag")) then
          do while (.true.)
             ok = getline_local()
             if (.not.ok) then
                errmsg = "Unexpected end of file inside frag block."
                goto 999
             end if
             lp = 1
             word = lgetword(line,lp)
             if (equal(word,"fend")) exit
          end do
       elseif (equal(word,"end")) then
          ! end of the input
          exit
       else
          ! maybe this is an atom, but if we can not tell, it could be a new or very old keyword 
          iz = zatguess(word)
          if (iz < 0) cycle

          ! check if this is an atom
          seed%nat = seed%nat + 1
          if (seed%nat > size(seed%is)) then
             call realloc(seed%x,3,2*seed%nat)
             call realloc(seed%is,2*seed%nat)
          end if
          ok = isinteger(iz,line,lp)
          ok = ok .and. isreal(seed%x(1,seed%nat),line,lp)
          ok = ok .and. isreal(seed%x(2,seed%nat),line,lp)
          ok = ok .and. isreal(seed%x(3,seed%nat),line,lp)
          if (.not.ok) then
             seed%nat = seed%nat - 1
             continue
          end if
          if (iz < 1 .or. iz > seed%nspc) then
             errmsg = "Atom type not found in SFAC list."
             goto 999
          end if
          seed%is(seed%nat) = iz
       end if
    end do

    if (seed%nspc == 0) then
       errmsg = "No SFAC information (atomic types) found."
       goto 999
    end if
    if (seed%nat == 0) then
       errmsg = "No atoms found."
       goto 999
    end if
    if (.not.havecell) then
       errmsg = "No cell found."
       goto 999
    end if
    seed%useabr = 1 ! use aa and bb

    if (iscent) then
       ! do we have the -1 operation already?
       ok = .true.
       do i = 1, seed%neqv
          if (all(abs(seed%rotm(:,:,i) + eyet) < 1d-12)) then
             ok = .false.
             exit
          endif
       end do
       if (.not.ok) then
          errmsg = "Found improper rotation in SYMM."
          goto 999
       end if
       n = seed%neqv
       do i = 1, n
          seed%rotm(1:3,1:3,n+i) = -seed%rotm(1:3,1:3,i) 
          seed%rotm(:,4,n+i) = seed%rotm(:,4,i) 
       end do
       seed%neqv = 2*n
    end if

    ! replicate the atoms using the local centering vectors passed in
    ! SYMM, if there are any
    if (lncv > 0) then
       do i = 1, lncv
          n = seed%nat
          do j = 1, n
             seed%nat = seed%nat + 1
             if (seed%nat > size(seed%is)) then
                call realloc(seed%x,3,2*seed%nat)
                call realloc(seed%is,2*seed%nat)
             end if
             seed%is(seed%nat) = seed%is(j)
             seed%x(:,seed%nat) = seed%x(:,j) + lcen(:,i)
             seed%x(:,seed%nat) = seed%x(:,seed%nat) - floor(seed%x(:,seed%nat))
          end do
       end do
    end if
    call realloc(seed%x,3,seed%nat)
    call realloc(seed%is,seed%nat)

    ! use the symmetry in this file
    seed%havesym = 1
    seed%checkrepeats = 1
    seed%findsym = -1
    call realloc(seed%rotm,3,4,seed%neqv)
    call realloc(seed%cen,3,seed%ncv)

999 continue
    call fclose(lu)

    ! restore the old values of x, y, and z
    if (iix) call setvariable("x",xo)
    if (iiy) call setvariable("y",yo)
    if (iiz) call setvariable("z",zo)

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = mol
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0

  contains
    function getline_local() result(ok_)
      logical :: ok_
      integer :: idx
      character(len=:), allocatable :: aux

      ok_ = getline_raw(lu,line,.false.)
      if (.not.ok_) return
      idx = index(line,"=",.true.)
      do while (idx == len_trim(line))
         ok_ = getline_raw(lu,aux,.false.)
         line = line(1:idx-1) // trim(aux)
         if (.not.ok_) return
         idx = index(line,"=",.true.)
      end do
    end function getline_local
  end subroutine read_shelx

  !> Read the structure from a gaussian cube file
  module subroutine read_cube(seed,file,mol,errmsg)
    use tools_io, only: fopen_read, fclose, nameguess, getline_raw
    use tools_math, only: matinv
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< Is this a molecule?
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu
    integer :: i, j, nstep(3), nn, iz, it
    real*8 :: x0(3), rmat(3,3), rdum, rx(3)
    logical :: ismo, ok
    character(len=:), allocatable :: line

    errmsg = "Error reading file."
    lu = fopen_read(file)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if

    ! the name of the seed is the first line
    ok = getline_raw(lu,line,.false.)
    if (.not.ok) goto 999
    seed%file = file
    if (len_trim(line) > 0) then
       seed%name = line
    else
       seed%name = file
    end if

    ! ignore the title lines
    read (lu,*,err=999)

    ! number of atoms and unit cell
    read (lu,*,err=999) seed%nat, x0
    ismo = (seed%nat < 0)
    seed%nat = abs(seed%nat)

    do i = 1, 3
       read (lu,*,err=999) nstep(i), rmat(:,i)
       rmat(:,i) = rmat(:,i) * nstep(i)
    end do

    seed%m_x2c = rmat
    rmat = transpose(rmat)
    rmat = matinv(rmat)
    seed%useabr = 2

    ! Atomic positions.
    allocate(seed%x(3,seed%nat),seed%is(seed%nat))
    allocate(seed%spc(2))
    nn = seed%nat
    seed%nat = 0
    do i = 1, nn
       read (lu,*,err=999) iz, rdum, rx
       if (iz > 0) then
          seed%nat = seed%nat + 1
          rx = matmul(rx - x0,rmat)
          seed%x(:,seed%nat) = rx - floor(rx)
          it = 0
          do j = 1, seed%nspc
             if (seed%spc(j)%z == iz) then
                it = j
                exit
             end if
          end do
          if (it == 0) then
             seed%nspc = seed%nspc + 1
             if (seed%nspc > size(seed%spc,1)) &
                call realloc(seed%spc,2*seed%nspc)
             seed%spc(seed%nspc)%z = iz
             seed%spc(seed%nspc)%name = nameguess(iz)
             it = seed%nspc
          end if
          seed%is(seed%nat) = it
       endif
    end do
    if (seed%nat /= nn) then
       call realloc(seed%x,3,seed%nat)
       call realloc(seed%is,seed%nat)
    end if
    call realloc(seed%spc,seed%nspc)

    errmsg = ""
999 continue
    call fclose(lu)

    ! no symmetry
    seed%havesym = 0
    seed%checkrepeats = 0
    seed%findsym = -1

    ! molecule
    seed%ismolecule = mol
    seed%havex0 = .true.
    seed%molx0 = x0

    ! rest of the seed information
    seed%isused = .true.
    seed%cubic = .false.
    seed%border = 0d0

  end subroutine read_cube

  !> Read the structure from a binary cube file
  module subroutine read_bincube(seed,file,mol,errmsg)
    use tools_io, only: fopen_read, fclose, nameguess, getline_raw
    use tools_math, only: matinv
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< Is this a molecule?
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu
    integer :: i, j, nstep(3), nn, iz, it
    real*8 :: x0(3), rmat(3,3), rdum, rx(3)

     errmsg = "Error reading file."
     lu = fopen_read(file,form="unformatted")
     if (lu < 0) then
        errmsg = "Error opening file."
        return
     end if

     ! number of atoms and unit cell
     read (lu,err=999) seed%nat, x0

     read (lu,err=999) nstep, rmat
     do i = 1, 3
        rmat(:,i) = rmat(:,i) * nstep(i)
     end do

     seed%m_x2c = rmat
     rmat = transpose(rmat)
     rmat = matinv(rmat)
     seed%useabr = 2
     
     ! Atomic positions.
     allocate(seed%x(3,seed%nat),seed%is(seed%nat))
     allocate(seed%spc(2))
     nn = seed%nat
     seed%nat = 0
     do i = 1, nn
        read (lu,err=999) iz, rdum, rx
        if (iz > 0) then
           seed%nat = seed%nat + 1
           rx = matmul(rx - x0,rmat)
           seed%x(:,seed%nat) = rx - floor(rx)
           it = 0
           do j = 1, seed%nspc
              if (seed%spc(j)%z == iz) then
                 it = j
                 exit
              end if
           end do
           if (it == 0) then
              seed%nspc = seed%nspc + 1
              if (seed%nspc > size(seed%spc,1)) &
                 call realloc(seed%spc,2*seed%nspc)
              seed%spc(seed%nspc)%z = iz
              seed%spc(seed%nspc)%name = nameguess(iz)
              it = seed%nspc
           end if
           seed%is(seed%nat) = it
        endif
     end do
     if (seed%nat /= nn) then
        call realloc(seed%x,3,seed%nat)
        call realloc(seed%is,seed%nat)
     end if
     call realloc(seed%spc,seed%nspc)

     errmsg = ""
999  continue
     call fclose(lu)

     ! no symmetry
     seed%havesym = 0
     seed%checkrepeats = 0
     seed%findsym = -1

     ! molecule
     seed%ismolecule = mol
     seed%havex0 = .true.
     seed%molx0 = x0

     ! rest of the seed information
     seed%isused = .true.
     seed%cubic = .false.
     seed%border = 0d0

  end subroutine read_bincube

  !> Read the crystal structure from a WIEN2k STRUCT file.
  !> Code adapted from the WIEN2k distribution.
  module subroutine read_wien(seed,file,mol,errmsg)
    use tools_io, only: fopen_read, ferror, zatguess, fclose, equal, equali
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed !< Output crystal seed
    character*(*), intent(in) :: file !< struct file
    logical, intent(in) :: mol !< is this a molecule?
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lut
    integer :: i, j, i1, i2, j1, iat, iat0, istart, it
    real*8 :: mat(3,3), rnot, rmt, pos(3), tau(3), znuc
    integer :: multw, iatnr, iz(3,3), jatom, mu, jri
    character*4 :: lattic, cform
    character*80 :: titel
    character*10 :: aname
    logical :: readall

    ! seed file
    errmsg = "Error reading file."
    seed%file = file

    ! first pass to see whether we have symmetry or not
    lut = fopen_read(file)
    if (lut < 0) then
       errmsg = "Error opening file."
       return
    end if

    READ(lut,102,err=999) TITEL
    READ(lut,103,err=999) LATTIC, seed%nat, cform
    READ(lut,100,err=999) seed%aa(1:3), seed%bb(1:3)
    DO JATOM=1,seed%nat
       READ(lut,1012,err=999) iatnr,pos,MULTW
       DO MU=1,MULTW-1
          READ(lut,1013,err=999) iatnr, pos
       end DO
       READ(lut,113,err=999) ANAME,JRI,RNOT,RMT,Znuc
       READ(lut,1051,err=999) ((mat(I1,J1),I1=1,3),J1=1,3)
    end DO
    READ(lut,114,err=999) seed%neqv

    readall = (seed%neqv <= 0)

    ! second pass -> actually process the information
    rewind(lut)
    READ(lut,102,err=999) TITEL
    seed%name = trim(TITEL)

    READ(lut,103,err=999) LATTIC, seed%nat, cform
102 FORMAT(A80)
103 FORMAT(A4,23X,I3,1x,a4,/,4X,4X) ! new

    seed%ncv = 1
    allocate(seed%cen(3,4))
    seed%cen = 0d0
    IF(LATTIC(1:1).EQ.'S'.OR.LATTIC(1:1).EQ.'P') THEN
       seed%ncv=1
    ELSE IF(LATTIC(1:1).EQ.'F') THEN
       seed%ncv=4
       seed%cen(1,2)=0.5d0
       seed%cen(2,2)=0.5d0
       seed%cen(2,3)=0.5d0
       seed%cen(3,3)=0.5d0
       seed%cen(1,4)=0.5d0
       seed%cen(3,4)=0.5d0
    ELSE IF(LATTIC(1:1).EQ.'B') THEN
       seed%ncv=2
       seed%cen(1,2)=0.5d0
       seed%cen(2,2)=0.5d0
       seed%cen(3,2)=0.5d0
    ELSE IF(LATTIC(1:1).EQ.'H') THEN
       seed%ncv=1
    ELSE IF(LATTIC(1:1).EQ.'R') THEN
       seed%ncv=1
    ELSE IF(LATTIC(1:3).EQ.'CXY') THEN
       seed%ncv=2
       seed%cen(1,2)=0.5d0
       seed%cen(2,2)=0.5d0
    ELSE IF(LATTIC(1:3).EQ.'CYZ') THEN
       seed%ncv=2
       seed%cen(2,2)=0.5d0
       seed%cen(3,2)=0.5d0
    ELSE IF(LATTIC(1:3).EQ.'CXZ') THEN
       seed%ncv=2
       seed%cen(1,2)=0.5d0
       seed%cen(3,2)=0.5d0
    ELSE
       errmsg = "Unknown lattice."
       goto 999
    END IF

    READ(lut,100,err=999) seed%aa(1:3), seed%bb(1:3)
100 FORMAT(6F10.5)
    if(seed%bb(3) == 0.d0) seed%bb(3)=90.d0
    seed%useabr = 1

    seed%nspc = 0
    allocate(seed%spc(2))
    allocate(seed%x(3,seed%nat),seed%is(seed%nat))
    iat = 0
    DO JATOM=1,seed%nat
       iat0 = iat
       iat = iat + 1
       if (iat > size(seed%is)) then
          call realloc(seed%x,3,2*iat)
          call realloc(seed%is,2*iat)
       end if
       READ(lut,1012,err=999) iatnr,seed%x(:,iat),MULTW

       istart = iat
       if (readall) then
          DO MU=1,MULTW-1
             iat = iat + 1
             if (iat > size(seed%is)) then
                call realloc(seed%x,3,2*iat)
                call realloc(seed%is,2*iat)
             end if
             READ(lut,1013,err=999) iatnr, seed%x(:,iat)
          end DO
       else
          DO MU=1,MULTW-1
             READ(lut,1013,err=999) iatnr, pos
          end DO
       end if

       READ(lut,113,err=999) ANAME,JRI,RNOT,RMT,Znuc
       aname = adjustl(aname)
       it = 0
       do i = 1, seed%nspc
          if (equali(aname,seed%spc(i)%name)) then
             it = i
             exit
          end if
       end do
       if (it == 0) then
          seed%nspc = seed%nspc + 1
          if (seed%nspc > size(seed%spc,1)) &
             call realloc(seed%spc,2*seed%nspc)
          seed%spc(seed%nspc)%name = aname
          seed%spc(seed%nspc)%z = zatguess(aname)
          it = seed%nspc
       end if
       do i = iat0+1, iat
          seed%is(i) = it
       end do
       READ(lut,1051,err=999) ((mat(I1,J1),I1=1,3),J1=1,3)
    end DO
113 FORMAT(A10,5X,I5,5X,F10.5,5X,F10.5,5X,F5.2)
1012 FORMAT(4X,I4,4X,F10.7,3X,F10.7,3X,F10.7,/15X,I2) ! new
1013 FORMAT(4X,I4,4X,F10.7,3X,F10.7,3X,F10.7) ! new
1051 FORMAT(20X,3F10.8)
    seed%nat = iat
    call realloc(seed%x,3,iat)
    call realloc(seed%is,iat)
    call realloc(seed%spc,seed%nspc)

    !.read number of symmetry operations, sym. operations
    READ(lut,114,err=999) seed%neqv
114 FORMAT(I4)

    if (seed%neqv > 0) then
       allocate(seed%rotm(3,4,seed%neqv))
       do i=1, seed%neqv
          read(lut,115,err=999) ((iz(i1,i2),i1=1,3),tau(i2),i2=1,3)
          do j=1,3
             seed%rotm(:,j,i)=dble(iz(j,:))
          enddo
          seed%rotm(:,4,i)=tau
       end do
    end if

115 FORMAT(3(3I2,F10.5,/))

    ! symmetry
    if (seed%neqv > 0) then
       seed%havesym = 1
       seed%findsym = 0
    else
       seed%havesym = 0
       seed%findsym = -1
    end if
    seed%checkrepeats = 0

    errmsg = ""
999 continue

    ! clean up
    call fclose(lut)

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = mol
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0

  end subroutine read_wien

  !> Read everything except the grid from a VASP POSCAR, etc. file
  !> If hastypes is present, it is equal to .true. if the file
  !> could be read successfully or .false. if the atomic types
  !> are missing.
  module subroutine read_vasp(seed,file,mol,hastypes,errmsg)
    use types, only: realloc
    use tools_io, only: fopen_read, getline_raw, isreal, &
       getword, zatguess, string, isinteger, nameguess, fclose
    use tools_math, only: detsym, matinv
    use param, only: bohrtoa
    class(crystalseed), intent(inout) :: seed !< Output crystal seed
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< Is this a molecule?
    logical, intent(out) :: hastypes
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu, lp, nn
    character(len=:), allocatable :: word, line
    logical :: ok, iscar

    integer :: i, j
    real*8 :: scalex, scaley, scalez, scale
    real*8 :: rprim(3,3), gprim(3,3)
    real*8 :: omegaa

    ! open
    errmsg = "Error reading file."
    hastypes = .true.
    lu = fopen_read(file)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if

    ! read the title and the scale line
    ok = getline_raw(lu,line,.true.)
    ok = getline_raw(lu,line,.true.)
    lp = 1
    ok = isreal(scalex,line,lp)
    ok = ok .and. isreal(scaley,line,lp)
    if (.not.ok) then
       scale = scalex
       scalex = 1d0
       scaley = 1d0
       scalez = 1d0
    else
       ok = isreal(scalez,line,lp)
       scale = 1d0
    end if

    ! read the cell vectors and calculate the metric tensor
    do i = 1, 3
       read (lu,*) rprim(1,i), rprim(2,i), rprim(3,i)
    end do
    if (scale < 0d0) then
       gprim = matmul(transpose(rprim),rprim)
       omegaa = sqrt(detsym(gprim))
       ! adjust the lengths to give the volume
       scale = abs(scale) / abs(omegaa)**(1d0/3d0)
    end if
    rprim(1,:) = rprim(1,:) * scalex * scale
    rprim(2,:) = rprim(2,:) * scaley * scale
    rprim(3,:) = rprim(3,:) * scalez * scale
    rprim = rprim / bohrtoa
    gprim = matmul(transpose(rprim),rprim)
    omegaa = sqrt(detsym(gprim))
    if (omegaa < 0d0) then
       errmsg = "Negative cell volume."
       goto 999
    end if
    seed%m_x2c = rprim
    rprim = matinv(rprim)
    seed%useabr = 2

    ! For versions >= 5.2, a line indicating the atom types appears here
    ok = getline_raw(lu,line,.false.)
    if (.not.ok) goto 999
    lp = 1
    word = getword(line,lp)
    if (zatguess(word) >= 0) then
       ! An atom name has been read -> read the rest of the line
       seed%nspc = 0
       if (allocated(seed%spc)) deallocate(seed%spc)
       allocate(seed%spc(2))
       do while (zatguess(word) >= 0)
          seed%nspc = seed%nspc + 1
          if (seed%nspc > size(seed%spc,1)) &
             call realloc(seed%spc,2*seed%nspc)
          seed%spc(seed%nspc)%name = word
          seed%spc(seed%nspc)%z = zatguess(word)
          word = getword(line,lp)
       end do
       call realloc(seed%spc,seed%nspc)
       ok = getline_raw(lu,line,.true.)
       if (.not.ok) goto 999
    else
       if (seed%nspc == 0) then
          errmsg = ""
          hastypes = .false.
          goto 999
       end if
    end if
    hastypes = .true.

    ! read number of atoms of each type
    lp = 1
    seed%nat = 0
    allocate(seed%is(10))
    do i = 1, seed%nspc
       ok = isinteger(nn,line,lp)
       if (.not.ok) then
          errmsg = "Too many atom types"
          goto 999
       end if
       do j = seed%nat+1, seed%nat+nn
          if (j > size(seed%is)) &
             call realloc(seed%is,2*(seed%nat+nn))
          seed%is(j) = i
       end do
       seed%nat = seed%nat + nn
    end do
    allocate(seed%x(3,seed%nat))
    call realloc(seed%is,seed%nat)

    ! check there are no more atoms in this line
    nn = -1 
    ok = isinteger(nn,line,lp)
    if (ok .and. nn /= -1) then
       errmsg = "Too few atom types"
       goto 999
    end if

    ! Read atomic positions (cryst. coords.)
    read(lu,*,err=999) line
    line = adjustl(line)
    if (line(1:1) == 's' .or. line(1:1) == 'S') then
       read(lu,*,err=999) line
       line = adjustl(line)
    endif
    iscar = .false.
    if (line(1:1) == 'd' .or. line(1:1) == 'D') then
       iscar = .false.
    elseif (line(1:1) == 'c' .or. line(1:1) == 'C' .or. line(1:1) == 'k' .or. line(1:1) == 'K') then
       iscar = .true.
    endif
    do i = 1, seed%nat
       read(lu,*,err=999) seed%x(:,i)
       if (iscar) &
          seed%x(:,i) = matmul(rprim,seed%x(:,i) / bohrtoa)
    enddo

    errmsg = ""
999 continue
    call fclose(lu)

    ! symmetry
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = mol
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_vasp

  !> Read the structure from an abinit DEN file (and similar files: ELF, LDEN, etc.)
  module subroutine read_abinit(seed,file,mol,errmsg)
    use tools_math, only: matinv
    use tools_io, only: fopen_read, nameguess, ferror, fclose
    use abinit_private, only: hdr_type, hdr_io
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed !< Output crystal seed
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< is this a molecule?
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu, fform0
    type(hdr_type) :: hdr
    integer :: i, iz
    real*8 :: rmat(3,3)

    errmsg = ""
    lu = fopen_read(file,"unformatted",errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if

    ! read the header of the DEN file
    call hdr_io(fform0,hdr,1,lu,errmsg)
    if (len_trim(errmsg) > 0) goto 999

    ! cell parameters
    rmat = hdr%rprimd(:,:)
    seed%m_x2c = rmat
    seed%useabr = 2

    ! types
    seed%nspc = hdr%ntypat
    allocate(seed%spc(seed%nspc))
    do i = 1, seed%nspc
       iz = nint(hdr%znucltypat(i))
       seed%spc(i)%z = iz
       seed%spc(i)%name = nameguess(iz)
    end do

    ! atoms
    seed%nat = hdr%natom
    allocate(seed%x(3,seed%nat),seed%is(seed%nat))
    do i = 1, seed%nat
       seed%x(:,i) = hdr%xred(:,i)
       seed%is(i) = hdr%typat(i)
    end do

    errmsg = ""
999 continue
    call fclose(lu)

    ! abinit has symmetry in hdr%nsym/hdr%symrel, but there is no
    ! distinction between pure centering and rotation operations, and
    ! the user may not want any symmetry - let critic2 guess.
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = mol
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_abinit

  ! The following code has been adapted from the elk distribution, version 1.3.2
  ! Copyright (C) 2002-2005 J. K. Dewhurst, S. Sharma and C. Ambrosch-Draxl.
  ! This file is distributed under the terms of the GNU General Public License.
  module subroutine read_elk(seed,file,mol,errmsg)
    use tools_io, only: fopen_read, getline_raw, equal, getword,&
       zatguess, nameguess, fclose, string
    use tools_math, only: matinv
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed !< Output crystal seed
    character*(*), intent(in) :: file !< input filename
    logical, intent(in) :: mol !< is this a molecule?
    character(len=:), allocatable, intent(out) :: errmsg

    character(len=:), allocatable :: line, atname
    integer :: lu, i, zat, j, lp, idx
    integer :: natoms
    logical :: ok

    errmsg = "Error reading file."
    lu = fopen_read(file,errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if

    ! ignore the 'scale' stuff
    do i = 1, 14
       read(lu,*,err=999)
    end do

    read(lu,'(3G18.10)',err=999) seed%m_x2c(:,1)
    read(lu,'(3G18.10)',err=999) seed%m_x2c(:,2)
    read(lu,'(3G18.10)',err=999) seed%m_x2c(:,3)
    seed%useabr = 2

    ok = getline_raw(lu,line,.false.)
    if (.not.ok) goto 999
    ok = getline_raw(lu,line,.true.)
    if (.not.ok) goto 999
    if (equal(line,'molecule')) then
       errmsg = "Isolated molecules not supported."
       goto 999
    end if

    seed%nat = 0
    allocate(seed%x(3,10),seed%is(10))
    read(lu,'(I4)',err=999) seed%nspc
    allocate(seed%spc(seed%nspc))
    do i = 1, seed%nspc
       ok = getline_raw(lu,line,.false.)
       if (.not.ok) goto 999
       lp = 1
       atname = getword(line,lp)
       do j = 1, len(atname)
          if (atname(j:j) == "'") atname(j:j) = " "
          if (atname(j:j) == '"') atname(j:j) = " "
       end do
       zat = zatguess(atname)
       if (zat == -1) then
          errmsg = "Species file name must start with an atomic symbol"
          goto 999
       end if
       seed%spc(i)%z = zat

       idx = index(atname,".in",.true.)
       if (idx > 1) then
          seed%spc(i)%name = trim(atname(1:idx-1))
       else
          seed%spc(i)%name = trim(atname)
       end if

       read(lu,*,err=999) natoms
       do j = 1, natoms
          seed%nat = seed%nat + 1
          if (seed%nat > size(seed%x,2)) then
             call realloc(seed%x,3,2*seed%nat)
             call realloc(seed%is,2*seed%nat)
          end if
          read(lu,*,err=999) seed%x(:,seed%nat)
          seed%is(seed%nat) = i
       end do
    end do
    call realloc(seed%x,3,seed%nat)
    call realloc(seed%is,seed%nat)

    errmsg = ""
999 continue
    call fclose(lu)

    ! symmetry
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = mol
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_elk

  !> Read the structure from an xyz/wfn/wfx file
  module subroutine read_mol(seed,file,fmt,rborder,docube,errmsg)
    use wfn_private, only: wfn_read_xyz_geometry, wfn_read_wfn_geometry, &
       wfn_read_wfx_geometry, wfn_read_fchk_geometry, wfn_read_molden_geometry,&
       wfn_read_log_geometry
    use param, only: isformat_xyz, isformat_wfn, isformat_wfx,&
       isformat_fchk, isformat_molden, isformat_gaussian
    use tools_io, only: equali
    use types, only: realloc

    class(crystalseed), intent(inout) :: seed !< Output crystal seed
    character*(*), intent(in) :: file !< Input file name
    integer, intent(in) :: fmt !< wfn/wfx/xyz
    real*8, intent(in) :: rborder !< user-defined border in bohr
    logical, intent(in) :: docube !< if true, make the cell cubic
    character(len=:), allocatable, intent(out) :: errmsg

    integer, allocatable :: z(:)
    character*(10), allocatable :: name(:) !< Atomic names
    integer :: i, j, it

    errmsg = ""
    if (fmt == isformat_xyz) then
       ! xyz
       call wfn_read_xyz_geometry(file,seed%nat,seed%x,z,name,errmsg)
    elseif (fmt == isformat_wfn) then
       ! wfn
       call wfn_read_wfn_geometry(file,seed%nat,seed%x,z,name,errmsg)
    elseif (fmt == isformat_wfx) then
       ! wfx
       call wfn_read_wfx_geometry(file,seed%nat,seed%x,z,name,errmsg)
    elseif (fmt == isformat_fchk) then
       ! fchk
       call wfn_read_fchk_geometry(file,seed%nat,seed%x,z,name,errmsg)
    elseif (fmt == isformat_molden) then
       ! molden (psi4)
       call wfn_read_molden_geometry(file,seed%nat,seed%x,z,name,errmsg)
    elseif (fmt == isformat_gaussian) then
       ! Gaussian output file
       call wfn_read_log_geometry(file,seed%nat,seed%x,z,name,errmsg)
    end if
    seed%useabr = 0
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0
    if (len_trim(errmsg) > 0) goto 999

    seed%nspc = 0
    allocate(seed%is(seed%nat),seed%spc(2))
    do i = 1, seed%nat
       it = 0
       do j = 1, seed%nspc
          if (equali(seed%spc(j)%name,name(i))) then
             it = j
             exit
          end if
       end do
       if (it == 0) then
          seed%nspc = seed%nspc + 1
          if (seed%nspc > size(seed%spc,1)) &
             call realloc(seed%spc,2*seed%nspc)
          seed%spc(seed%nspc)%name = name(i)
          seed%spc(seed%nspc)%z = z(i)
          it = seed%nspc
       end if
       seed%is(i) = it
    end do
    if (seed%nspc == 0) then
       errmsg = "No atomic species found."
       goto 999
    end if
    if (seed%nat == 0) then
       errmsg = "No atoms found."
       goto 999
    end if
    call realloc(seed%spc,seed%nspc)

    errmsg = ""
999 continue
    
    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = .true.
    seed%cubic = docube
    seed%border = rborder
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_mol

  !> Read the structure from a quantum espresso output (file) and
  !> return it as a crystal seed. If mol, the structure is assumed to
  !> be a molecule (currently, the only effect is that its value is
  !> passed to the %ismolecule field). If istruct is zero, read the
  !> last geometry; otherwise, read geometry number istruct. If an
  !> error condition is found, return the error message in errmsg
  !> (zero-length string if no error).
  module subroutine read_qeout(seed,file,mol,istruct,errmsg)
    use tools_io, only: fopen_read, getline_raw, isinteger, isreal,&
       zatguess, fclose, equali
    use tools_math, only: matinv
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed !< Crystal seed output
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< is this a molecule?
    integer, intent(in) :: istruct !< structure number
    character(len=:), allocatable, intent(out) :: errmsg

    type(crystalseed), allocatable :: seedaux(:)
    integer :: nseed

    call read_all_qeout(nseed,seedaux,file,mol,istruct,errmsg)
    if (allocated(seedaux) .and. nseed >= 1) then
       seed = seedaux(1)
    end if

  end subroutine read_qeout

  !> Read the structure from a quantum espresso input
  module subroutine read_qein(seed,file,mol,errmsg)
    ! This subroutine has been adapted from parts of the Quantum
    ! ESPRESSO code, version 4.3.2.  
    ! Copyright (C) 2002-2009 Quantum ESPRESSO group
    ! This file is distributed under the terms of the
    ! GNU General Public License. See the file `License'
    ! in the root directory of the present distribution,
    ! or http://www.gnu.org/copyleft/gpl.txt .
    use tools_io, only: fopen_read, getline_raw, lower, getword,&
       equal, zatguess, fclose
    use tools_math, only: matinv
    use param, only: bohrtoa
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed !< Output crystal seed
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< is this a molecule?
    character(len=:), allocatable, intent(out) :: errmsg

    integer, parameter :: dp = selected_real_kind(14,200)
    integer, parameter :: ntypx = 10
    integer, parameter :: nsx = ntypx
    integer, parameter :: nspinx = 2
    integer, parameter :: lmaxx = 3
    integer, parameter :: lqmax = 2*lmaxx+1

    !!! Up to date with quantum espresso 6.3. More recent versions may
    !!! need additional keywords.

    ! from QE
    ! namelist control
    character(len=80) :: title, calculation, verbosity, restart_mode,&
       disk_io, memory
    character(len=10) :: point_label_type
    character(len=256) :: input_xml_schema_file
    integer :: nstep, iprint, isave, ndr, ndw, gdir, nppstr, nberrycyc, &
       printwfc
    logical :: tstress, tprnfor, tefield, tefield2, lelfield, dipfield, &
       lberry, wf_collect, saverho, tabps, lkpoint_dir, use_wannier, &
       lecrpa, tqmmm, lorbm, lfcpopt, lfcpdyn, gate
    real*8 :: dt, refg, max_seconds, ekin_conv_thr, etot_conv_thr, &
       forc_conv_thr
    character(len=256) :: outdir, prefix, pseudo_dir, wfcdir, vdw_table_name
    namelist /control/ title, calculation, verbosity, restart_mode,  &
       nstep, iprint, isave, tstress, tprnfor, dt, ndr, ndw, outdir,   &
       prefix, wfcdir, max_seconds, ekin_conv_thr, etot_conv_thr,      &
       forc_conv_thr, pseudo_dir, disk_io, tefield, dipfield, lberry,  &
       gdir, nppstr, wf_collect, printwfc, lelfield, nberrycyc, refg,  &
       tefield2, saverho, tabps, lkpoint_dir, use_wannier, lecrpa,     &
       vdw_table_name, tqmmm, lorbm, memory, point_label_type,         &
       lfcpopt, lfcpdyn, input_xml_schema_file, gate

    ! namelist system
    integer :: ibrav = 14
    real*8 :: celldm(6) = 0.d0
    real*8 :: a, b, c, cosab, cosac, cosbc
    integer :: nat = 0
    integer :: ntyp = 0
    integer :: origin_choice = 1 
    integer :: space_group = 0
    logical :: rhombohedral = .TRUE.
    logical :: uniqueb=.FALSE.
    real*8 :: tot_charge, tot_magnetization, ecutwfc, ecutrho, degauss, &
       ecfixed, qcutz, q2sigma, starting_magnetization(nsx), &
       starting_ns_eigenvalue(lqmax,nspinx,nsx), hubbard_u(nsx), &
       hubbard_alpha(nsx), a_pen(10,nspinx), sigma_pen(10), alpha_pen(10), &
       emaxpos, eopreg, eamp, lambda, fixed_magnetization(3), angle1(nsx), &
       angle2(nsx), b_field(3), sic_epsilon, sic_alpha, london_s6, london_rcut, &
       xdm_a1, xdm_a2, ts_sr, esm_efield, esm_w, &
       block_1, block_2, block_height, ecutfock, ecutvcut, esm_a, esm_zb, exx_fraction, &
       fcp_mass, fcp_mdiis_step, fcp_mu, fcp_relax_crit, fcp_relax_step, fcp_tempw, &
       hubbard_beta(nsx), hubbard_j0(nsx), hubbard_j(3,nsx), localization_thr, london_c6(nsx), &
       london_rvdw(nsx), ref_alat, scdmden, scdmgrd, screening_parameter, starting_charge(nsx), &
       ts_vdw_econv_thr, yukawa, zgate
    integer :: nbnd, nr1, nr2, nr3, nr1s, nr2s, nr3s, nr1b, nr2b, nr3b, &
       nspin, edir, report, xdm_usehigh, esm_nfit, esm_debug_gpmax, &
       dftd3_version, fcp_mdiis_size, lda_plus_u_kind, n_proj, nqx1, &
       nqx2, nqx3
    character(len=80) :: occupations, smearing, input_dft, u_projection_type, &
       constrained_magnetization, sic, assume_isolated
    logical :: nosym, noinv, nosym_evc, force_symmorphic, lda_plus_u, la2f, &
       step_pen, noncolin, lspinorb, starting_spin_angle, no_t_rev, force_pairing, &
       spline_ps, one_atom_occupations, london, xdm, xdm_onlyc, xdm_fixc6, &
       xdm_usec9, ts, ts_onlyc, esm_debug, &
       ace, block, dftd3_threebody, lforcet, relaxz, scdm, ts_vdw, ts_vdw_isolated, &
       use_all_frac, x_gamma_extrapolation
    character(len=3) :: esm_bc
    character(len=80) :: exxdiv_treatment, vdw_corr
    character(len=8) :: fcp_relax

    namelist /system/ ibrav, celldm, a, b, c, cosab, cosac, cosbc, nat,     &
       ntyp, nbnd, ecutwfc, ecutrho, nr1, nr2, nr3, nr1s, nr2s, nr3s, nr1b, & 
       nr2b, nr3b, nosym, nosym_evc, noinv, force_symmorphic, starting_magnetization, &
       occupations, degauss, nspin, ecfixed, qcutz, q2sigma, lda_plus_u, &
       hubbard_u, hubbard_alpha, edir, emaxpos, eopreg, eamp, smearing, &
       starting_ns_eigenvalue, u_projection_type, input_dft, la2f, assume_isolated, &
       noncolin, lspinorb, starting_spin_angle, lambda, angle1, angle2, report, &
       constrained_magnetization, b_field, fixed_magnetization, sic, sic_epsilon, &
       force_pairing, sic_alpha, tot_charge, tot_magnetization, spline_ps, &
       one_atom_occupations, london, london_s6, london_rcut, xdm, xdm_onlyc, &
       xdm_fixc6, xdm_usec9, xdm_usehigh, xdm_a1, xdm_a2, ts, ts_onlyc, ts_sr, &
       step_pen, a_pen, sigma_pen, alpha_pen, no_t_rev, esm_bc, esm_efield, &
       esm_w, esm_nfit, esm_debug, esm_debug_gpmax, use_all_frac, starting_charge, &
       lda_plus_u_kind, hubbard_j, hubbard_j0, hubbard_beta, nqx1, nqx2, nqx3, &
       ecutfock, localization_thr, scdm, ace, scdmden, scdmgrd, n_proj, exxdiv_treatment, &
       x_gamma_extrapolation, yukawa, ecutvcut, exx_fraction, screening_parameter, &
       ref_alat, lforcet, vdw_corr, london_c6, london_rvdw, dftd3_version, dftd3_threebody, &
       ts_vdw, ts_vdw_isolated, ts_vdw_econv_thr, esm_a, esm_zb, fcp_mu, fcp_mass, &
       fcp_tempw, fcp_relax, fcp_relax_step, fcp_relax_crit, fcp_mdiis_size, &
       fcp_mdiis_step, space_group, uniqueb, origin_choice, rhombohedral, &
       zgate, relaxz, block, block_1, block_2, block_height

    ! namelist electrons
    real*8 :: emass, emass_cutoff, ortho_eps, electron_damping, ekincw, fnosee, &
       ampre, grease, diis_hcut, diis_wthr, diis_delt, diis_fthr, diis_temp, &
       diis_achmix, diis_g0chmix, diis_g1chmix, diis_rothr, diis_ethr, mixing_beta,&
       diago_thr_init, conv_thr, lambda_cold, fermi_energy, rotmass, occmass,&
       occupation_damping, rotation_damping, etresh, passop, efield, efield_cart(3),&
       efield2, emass_emin, emass_cutoff_emin, electron_damping_emin, dt_emin
    character(len=80) :: orthogonalization, electron_dynamics, electron_velocities,&
       electron_temperature, startingwfc, mixing_mode, diagonalization, startingpot,&
       rotation_dynamics, occupation_dynamics, efield_phase
    integer :: ortho_max, electron_maxstep, diis_size, diis_nreset, diis_maxstep, &
       diis_nchmix, diis_nrot(3), mixing_ndim, diago_cg_maxiter, diago_david_ndim, &
       mixing_fixed_ns, n_inner, niter_cold_restart, maxiter, niter_cg_restart, &
       epol, epol2
    logical :: diis_rot, diis_chguess, diago_full_acc, tcg, real_space, tqr,&
       occupation_constraints, &
       scf_must_converge, tq_smoothing, tbeta_smoothing, adaptive_thr, tcpbo
    namelist /electrons/ emass, emass_cutoff, orthogonalization, &
       electron_maxstep, ortho_eps, ortho_max, electron_dynamics,   &
       electron_damping, electron_velocities, electron_temperature, &
       ekincw, fnosee, ampre, grease,                               &
       diis_size, diis_nreset, diis_hcut,                           &
       diis_wthr, diis_delt, diis_maxstep, diis_rot, diis_fthr,     &
       diis_temp, diis_achmix, diis_g0chmix, diis_g1chmix,          &
       diis_nchmix, diis_nrot, diis_rothr, diis_ethr, diis_chguess, &
       mixing_mode, mixing_beta, mixing_ndim, mixing_fixed_ns,      &
       tqr, diago_cg_maxiter, diago_david_ndim, diagonalization ,   &
       startingpot, startingwfc , conv_thr,                         &
       diago_thr_init, n_inner, fermi_energy, rotmass, occmass,     &
       rotation_damping, occupation_damping, rotation_dynamics,     &
       occupation_dynamics, tcg, maxiter, etresh, passop, epol,     &
       efield, epol2, efield2, diago_full_acc,                      &
       occupation_constraints, niter_cg_restart,                    &
       niter_cold_restart, lambda_cold, efield_cart, real_space,    &
       scf_must_converge, tq_smoothing, tbeta_smoothing, adaptive_thr, &
       tcpbo,emass_emin, emass_cutoff_emin, electron_damping_emin,  &
       dt_emin, efield_phase

    ! namelist ions
    character(len=80) :: phase_space, ion_dynamics, ion_positions, ion_velocities,&
       ion_temperature, pot_extrapolation, wfc_extrapolation
    integer, parameter :: nhclm   = 4
    integer, parameter :: max_nconstr = 100
    integer :: nhpcl, nhptyp, nhgrp(nsx), ndega, ion_nstepe, ion_maxstep, nraise,&
       bfgs_ndim, fe_nstep, sw_nstep, eq_nstep, n_muller, np_muller
    real*8 :: ion_radius(nsx), ion_damping, tempw, fnosep(nhclm), tolp, fnhscl(nsx),&
       amprp(nsx), greasp, upscale, delta_t, trust_radius_max, trust_radius_min,&
       trust_radius_ini, w_1, w_2, sic_rloc, g_amplitude, fe_step(max_nconstr)
    logical :: tranp(nsx), refold_pos, remove_rigid_rot, l_mplathe, l_exit_muller

    namelist /ions/ phase_space, ion_dynamics, ion_radius, ion_damping,  &
       ion_positions, ion_velocities, ion_temperature,      &
       tempw, fnosep, nhgrp, fnhscl, nhpcl, nhptyp, ndega, tranp,   &
       amprp, greasp, tolp, ion_nstepe, ion_maxstep,        &
       refold_pos, upscale, delta_t, pot_extrapolation,     &
       wfc_extrapolation, nraise, remove_rigid_rot,         &
       trust_radius_max, trust_radius_min,                  &
       trust_radius_ini, w_1, w_2, bfgs_ndim, sic_rloc,     &
       fe_step, fe_nstep, sw_nstep, eq_nstep, g_amplitude, &
       l_mplathe, n_muller, np_muller, l_exit_muller

    ! namelist cell
    character(len=80) :: cell_parameters, cell_dynamics, cell_velocities, &
       cell_temperature, cell_dofree
    real(dp) :: press, wmass, temph, fnoseh, greash, cell_factor, cell_damping,&
       press_conv_thr
    integer :: cell_nstepe = 1
    namelist /cell/ cell_parameters, cell_dynamics, cell_velocities, &
       press, wmass, cell_temperature, temph, fnoseh,   &
       cell_dofree, greash, cell_factor, cell_nstepe,   &
       cell_damping, press_conv_thr

    ! local to this routine
    integer :: lu, ios, lp, i, j
    character(len=:), allocatable :: line, word
    character*10 :: atm
    real*8 :: r(3,3)
    integer :: iunit, cunit
    integer, parameter :: icrystal = 1
    integer, parameter :: ibohr = 2
    integer, parameter :: iang = 3
    integer, parameter :: ialat = 4

    ! open
    errmsg = ""
    lu = fopen_read(file,errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if
    r = 0d0
    calculation = ""

    ! read the namelists
    read(lu,control,iostat=ios)
    if (ios /= 0) then
       errmsg = "Wrong namelist control."
       goto 999
    end if
    read(lu,system,iostat=ios)
    if (ios/=0) then
       errmsg = "Wrong namelist system."
       goto 999
    end if
    read(lu,electrons,iostat=ios)
    if (ios/=0) then
       errmsg = "Wrong namelist electrons."
       goto 999
    end if
    if (trim(calculation)=='relax'.or.trim(calculation)=='md'.or.&
       trim(calculation)=='vc-relax'.or.trim(calculation)=='vc-md'.or.&
       trim(calculation)=='cp'.or.trim(calculation)=='vc-cp'.or.&
       trim(calculation)=='smd'.or.trim(calculation)=='cp-wf') then
       read(lu,ions,iostat=ios)
       if (ios/=0) then
          errmsg = "Wrong namelist ions."
          goto 999
       end if
    endif
    if (trim(calculation)=='vc-relax'.or.trim(calculation)=='vc-md'.or.&
       trim(calculation)=='vc-cp') then
       read(lu,cell,iostat=ios)
       if (ios/=0) then
          errmsg = "Wrong namelist ions."
          goto 999
       end if
    end if

    ! allocate space for atoms
    seed%nat = nat
    seed%nspc = ntyp
    allocate(seed%x(3,nat),seed%is(nat),seed%spc(ntyp))

    ! read the cards
    iunit = icrystal
    cunit = ialat
    do while (getline_raw(lu,line))
       line = lower(line)
       lp = 1
       word = getword(line,lp)
       if (equal(word,'atomic_species')) then
          do i = 1, ntyp
             read (lu,*,iostat=ios) seed%spc(i)%name
             if (ios/=0) then
                errmsg = "Error reading atomic species."
                goto 999
             end if
             seed%spc(i)%z = zatguess(seed%spc(i)%name)
          end do

       else if (equal(word,'atomic_positions')) then
          word = getword(line,lp)
          if (equal(word,"crystal")) then
             iunit = icrystal
          elseif (equal(word,"bohr")) then
             iunit = ibohr
          elseif (equal(word,"angstrom")) then
             iunit = iang
          elseif (equal(word,"alat")) then
             iunit = ialat
          else
             iunit = ialat
          end if
          do i = 1, nat
             read (lu,*,iostat=ios) atm, seed%x(:,i)
             if (ios/=0) then
                errmsg = "Error reading atomic positions."
                goto 999
             end if
             seed%is(i) = 0
             do j = 1, seed%nspc
                if (equal(seed%spc(j)%name,atm)) then
                   seed%is(i) = j
                   exit
                end if
             end do
             if (seed%is(i) == 0) then
                errmsg = "Could not find atomic species "//trim(atm)//"."
                goto 999
             end if
          end do
       elseif (equal(word,'cell_parameters')) then
          word = getword(line,lp)
          cunit = ialat
          if (equal(word,"bohr")) then
             cunit = ibohr
          elseif (equal(word,"angstrom")) then
             cunit = iang
          elseif (equal(word,"alat")) then
             cunit = ialat
          elseif (len_trim(word) == 0) then
             cunit = ialat
          else
             cunit = ibohr
          end if
          do i = 1, 3
             read (lu,*,iostat=ios) (r(i,j),j=1,3)
             if (ios/=0) then
                errmsg = "Error reading cell parameters."
                goto 999
             end if
          end do
       endif
    end do

    ! figure it out
    if (ibrav == 0) then
       if (cunit == ialat) then
          if (celldm(1) /= 0.D0) r = r * celldm(1)
       elseif (cunit == iang) then
          r = r / bohrtoa
       end if
       r = transpose(r)
    else
       call qe_latgen(ibrav,celldm,r(:,1),r(:,2),r(:,3),errmsg)
       if (len_trim(errmsg) > 0) goto 999
    endif

    ! fill the cell metrics
    seed%m_x2c = r
    r = matinv(seed%m_x2c)
    seed%useabr = 2

    ! do the atom stuff
    do i = 1, nat
       if (iunit == ialat) then
          seed%x(:,i) = matmul(r,seed%x(:,i) * celldm(1))
       elseif (iunit == ibohr) then
          seed%x(:,i) = matmul(r,seed%x(:,i))
       elseif (iunit == iang) then
          seed%x(:,i) = matmul(r,seed%x(:,i) / bohrtoa)
       endif
       seed%x(:,i) = seed%x(:,i) - floor(seed%x(:,i))
    end do

    errmsg = ""
999 continue
    call fclose(lu)

    ! symmetry
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = mol
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_qein

  !> Read the structure from a crystal output
  module subroutine read_crystalout(seed,file,mol,errmsg)
    use tools_io, only: fopen_read, getline_raw, isinteger, isreal,&
       zatguess, fclose, equali
    use tools_math, only: matinv
    use param, only: bohrtoa
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed !< Output crystal seed
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< is this a molecule?
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu, i, j
    character(len=:), allocatable :: line
    integer :: idum, iz, lp
    real*8 :: r(3,3), x(3)
    logical :: ok, iscrystal
    character*(10) :: ats

    errmsg = ""
    lu = fopen_read(file,errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if

    errmsg = "Error reading file."
    r = 0d0
    iscrystal = .false.
    allocate(seed%x(3,10),seed%is(10),seed%spc(2))
    seed%nat = 0
    seed%nspc = 0
    ! rewind and read the correct structure
    rewind(lu)
    do while (getline_raw(lu,line))
       if (index(line,"CRYSTAL CALCULATION") > 0) then
          iscrystal = .true.
       elseif (index(line,"DIRECT LATTICE VECTORS CARTESIAN COMPONENTS") > 0) then
          ok = getline_raw(lu,line)
          if (.not.ok) goto 999
          do i = 1, 3
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
             lp = 1
             ok = isreal(r(i,1),line,lp)
             ok = ok.and.isreal(r(i,2),line,lp)
             ok = ok.and.isreal(r(i,3),line,lp)
             if (.not.ok) then
                errmsg = "Wrong lattice vectors."
                goto 999
             end if
          end do
          r = r / bohrtoa
       elseif (index(line,"CARTESIAN COORDINATES - PRIMITIVE CELL") > 0) then
          do i = 1, 3
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
          end do
          line = ""
          seed%nat = 0
          do while (.true.)
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
             if (len_trim(line) < 1) exit
             seed%nat = seed%nat + 1
             if (seed%nat > size(seed%x,2)) then
                call realloc(seed%x,3,2*seed%nat)
                call realloc(seed%is,2*seed%nat)
             end if
             read (line,*,err=999) idum, iz, ats, x
             seed%x(:,seed%nat) = x / bohrtoa
             seed%is(seed%nat) = 0
             do j = 1, seed%nspc
                if (equali(trim(ats),seed%spc(j)%name)) then
                   seed%is(seed%nat) = j
                   exit
                end if
             end do
             if (seed%is(seed%nat) == 0) then
                seed%nspc = seed%nspc + 1
                if (seed%nspc > size(seed%spc,1)) &
                   call realloc(seed%spc,2*seed%nspc)
                seed%spc(seed%nspc)%name = trim(ats)
                seed%spc(seed%nspc)%z = zatguess(ats)
                seed%is(seed%nat) = seed%nspc
             end if
          end do
       end if
    end do
    call realloc(seed%x,3,seed%nat)
    call realloc(seed%is,seed%nat)
    call realloc(seed%spc,seed%nspc)

    if (.not.iscrystal) then
       errmsg = "Only CRYSTAL calculations supported (no MOLECULE, SLAB or POLYMER)."
       goto 999
    end if
    if (all(r == 0d0)) then
       errmsg = "Could not find lattice vectors."
       goto 999
    end if

    ! cell
    seed%m_x2c = transpose(r)
    r = matinv(seed%m_x2c)
    seed%useabr = 2

    ! atoms
    do i = 1, seed%nat
       seed%x(:,i) = matmul(r,seed%x(:,i))
       seed%x(:,i) = seed%x(:,i) - floor(seed%x(:,i))
    end do

    errmsg = ""
999 continue
    call fclose(lu)

    ! no symmetry
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = mol
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_crystalout

  !> Read the structure from a siesta OUT input
  module subroutine read_siesta(seed,file,mol,errmsg)
    use tools_io, only: fopen_read, nameguess, fclose
    use tools_math, only: matinv
    use param, only: bohrtoa
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed !< Crystal seed output
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< is this a molecule?
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu
    real*8 :: r(3,3)
    integer :: i, idum

    errmsg = ""
    ! open
    lu = fopen_read(file,errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if
    errmsg = "Error reading file."

    ! the lattice vectors
    do i = 1, 3
       read (lu,*,err=999) r(i,:)
    end do
    r = r / bohrtoa

    ! the atoms
    seed%nspc = 0
    read (lu,*,err=999) seed%nat
    allocate(seed%x(3,seed%nat),seed%is(seed%nat),seed%spc(2))
    do i = 1, seed%nat
       read (lu,*,err=999) seed%is(i), idum, seed%x(:,i)
       if (idum > size(seed%spc,1)) &
          call realloc(seed%spc,2*idum)
       seed%nspc = max(seed%nspc,seed%is(i))
       seed%spc(seed%is(i))%z = idum
       seed%spc(seed%is(i))%name = nameguess(idum)
    end do
    call realloc(seed%spc,seed%nspc)

    ! fill the cell metrics
    seed%m_x2c = transpose(r)
    seed%useabr = 2

    errmsg = ""
999 continue
    call fclose(lu)

    ! no symmetry
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = mol
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_siesta

  !> Read the structure from a file in DFTB+ gen format.
  module subroutine read_dftbp(seed,file,rborder,docube,errmsg)
    use tools_math, only: matinv
    use tools_io, only: fopen_read, getline, lower, equal, &
       getword, zatguess, nameguess, fclose
    use param, only: bohrtoa
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed !< Crystal seed output
    character*(*), intent(in) :: file !< Input file name
    real*8, intent(in) :: rborder !< user-defined border in bohr
    logical, intent(in) :: docube !< if true, make the cell cubic
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu
    real*8 :: r(3,3)
    integer :: i, iz, idum, lp
    logical :: ok, molout
    character*1 :: isfrac
    character(len=:), allocatable :: line, word

    ! open
    molout = .false.
    errmsg = ""
    lu = fopen_read(file,errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if
    errmsg = "Error reading file."

    ! number of atoms and type of coordinates
    ok = getline(lu,line)
    if (.not.ok) goto 999
    read (line,*,err=999) seed%nat, isfrac
    isfrac = lower(isfrac)
    if (.not.(equal(isfrac,"f").or.equal(isfrac,"c").or.equal(isfrac,"s"))) then
       errmsg = 'Wrong coordinate selector.'
       goto 999
    end if
    allocate(seed%x(3,seed%nat),seed%is(seed%nat))

    ! atom types
    seed%nspc = 0
    allocate(seed%spc(2))
    ok = getline(lu,line)
    if (.not.ok) goto 999
    lp = 1
    word = getword(line,lp)
    iz = zatguess(word)
    do while (iz >= 0)
       seed%nspc = seed%nspc + 1
       if (seed%nspc > size(seed%spc,1)) &
          call realloc(seed%spc,2*seed%nspc)
       seed%spc(seed%nspc)%z = iz
       seed%spc(seed%nspc)%name = nameguess(iz)
       word = getword(line,lp)
       iz = zatguess(word)
    end do
    if (seed%nspc == 0) then
       errmsg = 'No atomic types found.'
       goto 999
    end if
    call realloc(seed%spc,seed%nspc)

    ! read atomic positions
    do i = 1, seed%nat
       ok = getline(lu,line)
       if (.not.ok) goto 999
       read (line,*,err=999) idum, seed%is(i), seed%x(:,i)
       if (isfrac /= "f") &
          seed%x(:,i) = seed%x(:,i) / bohrtoa
    end do

    ! read lattice vectors, if they exist
    ok = getline(lu,line)
    if (ok) then
       do i = 1, 3
          ok = getline(lu,line,.true.)
          read (line,*) r(i,:)
       end do
       r = r / bohrtoa

       ! fill the cell metrics
       seed%m_x2c = transpose(r)
       r = matinv(seed%m_x2c)
       if (isfrac == "c") then
          errmsg = 'Lattice plus C not supported.'
          goto 999
       elseif (isfrac == "s") then
          do i = 1, seed%nat
             seed%x(:,i) = matmul(r,seed%x(:,i))
          end do
       end if
       seed%useabr = 2
       molout = .false.
    else
       ! molecule and no lattice -> set up the origin and the molecular cell
       if (isfrac == "f" .or. isfrac == "s") then
          errmsg = 'S or F coordinates but no lattice vectors.'
          goto 999
       end if
       seed%useabr = 0
       molout = .true.
    end if

    errmsg = ""
999 continue
    call fclose(lu)

    ! no symmetry
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = molout
    seed%cubic = docube
    seed%border = rborder
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_dftbp

  !> Read the structure from an xsf file.
  module subroutine read_xsf(seed,file,rborder,docube,errmsg)
    use tools_io, only: fopen_read, fclose, getline_raw, lgetword, nameguess, equal,&
       zatguess, isinteger, getword, isreal, lower, string
    use tools_math, only: matinv
    use param, only: bohrtoa
    use types, only: realloc
    use hashmod, only: hash
    class(crystalseed), intent(inout) :: seed !< Crystal seed output
    character*(*), intent(in) :: file !< Input file name
    real*8, intent(in) :: rborder !< user-defined border in bohr
    logical, intent(in) :: docube !< if true, make the cell cubic
    character(len=:), allocatable, intent(out) :: errmsg

    character(len=:), allocatable :: line, word, name
    character*10 :: atn, latn
    integer :: lu, lp, i, j, iz, it
    real*8 :: r(3,3), x(3)
    logical :: ok, ismol
    type(hash) :: usen

    ! open
    ismol = .false.
    errmsg = ""
    lu = fopen_read(file)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if

    errmsg = "Error reading file."
    do while (.true.)
       ok = getline_raw(lu,line)
       if (.not.ok) exit
       lp = 1
       word = lgetword(line,lp)
       if (equal(word,"primvec")) then
          do i = 1, 3
             read (lu,*,err=999) r(i,:)
          end do
          r = r / bohrtoa
          ismol = .false.
       elseif (equal(word,"primcoord")) then
          read (lu,*,err=999) seed%nat
          allocate(seed%x(3,seed%nat),seed%is(seed%nat))
          seed%nspc = 0
          allocate(seed%spc(2))
          do i = 1, seed%nat
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
             lp = 1
             ok = isinteger(iz,line,lp)
             if (ok) then
                ! Z x y z
                name = nameguess(iz,.true.)
             else
                word = getword(line,lp)
                name = trim(adjustl(word))
                iz = zatguess(name)
             end if
             ok = isreal(seed%x(1,i),line,lp)
             ok = ok.and.isreal(seed%x(2,i),line,lp)
             ok = ok.and.isreal(seed%x(3,i),line,lp)
             if (.not.ok) then
                errmsg = 'Wrong atomic position.'
                goto 999
             end if
             seed%x(:,i) = seed%x(:,i) / bohrtoa

             it = 0
             do j = 1, seed%nspc
                if (seed%spc(j)%z == iz) then
                   it = j
                   exit
                end if
             end do
             if (it == 0) then
                seed%nspc = seed%nspc + 1
                if (seed%nspc > size(seed%spc,1)) &
                   call realloc(seed%spc,2*seed%nspc)
                seed%spc(seed%nspc)%z = iz
                seed%spc(seed%nspc)%name = name
                it = seed%nspc
             end if
             seed%is(i) = it
          end do
          ismol = .false.
       elseif (equal(word,"atoms")) then
          ismol = .true.
          call usen%init()
          seed%nat = 0
          seed%nspc = 0
          allocate(seed%x(3,10),seed%spc(5),seed%is(10))
          do while (getline_raw(lu,line))
             if (len_trim(line) == 0) exit
             
             read (line,*,err=999) atn, x
             seed%nat = seed%nat + 1
             if (seed%nat > size(seed%x,2)) then
                call realloc(seed%x,3,2*seed%nat)
                call realloc(seed%is,2*seed%nat)
             end if
             seed%x(:,seed%nat) = x / bohrtoa

             iz = zatguess(atn)
             if (iz < 0) then
                errmsg = "Unknown atomic symbol: "//trim(atn)//"."
                goto 999
             end if

             latn = lower(atn)
             if (usen%iskey(latn)) then
                seed%is(seed%nat) = usen%get(latn,1)
             else
                seed%nspc = seed%nspc + 1
                if (seed%nspc > size(seed%spc,1)) &
                   call realloc(seed%spc,2*seed%nspc)
                seed%spc(seed%nspc)%name = trim(atn)
                seed%spc(seed%nspc)%z = iz
                seed%spc(seed%nspc)%qat = 0d0
                call usen%put(latn,seed%nspc)
                seed%is(seed%nat) = seed%nspc
             end if
          end do
          call realloc(seed%x,3,seed%nat)
          call realloc(seed%is,seed%nat)
          call realloc(seed%spc,seed%nspc)
       end if
    end do
    call realloc(seed%spc,seed%nspc)
    if (seed%nat == 0) then
       errmsg = "No atoms found."
       goto 999
    end if
    if (seed%nspc == 0) then
       errmsg = "No atomic species found."
       goto 999
    end if

    if (.not.ismol) then
       ! fill the cell metrics
       seed%m_x2c = transpose(r)
       r = matinv(seed%m_x2c)
       seed%useabr = 2
       
       ! convert atoms to crystallographic
       do i = 1, seed%nat
          seed%x(:,i) = matmul(r,seed%x(:,i))
       end do
    else
       seed%useabr = 0
    end if

    errmsg = ""
999 continue
    call fclose(lu)

    ! symmetry
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = ismol
    seed%cubic = docube
    seed%border = rborder
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_xsf

  !> Read the structure from a pwc file.
  module subroutine read_pwc(seed,file,mol,errmsg)
    use tools_math, only: matinv
    use tools_io, only: fopen_read, fclose, zatguess
    class(crystalseed), intent(inout) :: seed !< Crystal seed output
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< is this a molecule?
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu
    integer :: version, i
    character*3, allocatable :: atm(:)
    real*8 :: r(3,3)

    errmsg = ""
    ! open
    lu = fopen_read(file,errstop=.false.,form="unformatted")
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if
    errmsg = "Error reading file."

    ! header
    read (lu,err=999) version
    read (lu,err=999) seed%nspc, seed%nat

    ! species
    allocate(atm(seed%nspc),seed%spc(seed%nspc))
    read (lu,err=999) atm
    do i = 1, seed%nspc
       seed%spc(i)%name = trim(atm(i))
       seed%spc(i)%z = zatguess(seed%spc(i)%name)
    end do
    deallocate(atm)

    ! read the rest
    allocate(seed%x(3,seed%nat),seed%is(seed%nat))
    read (lu,err=999) seed%is
    read (lu,err=999) seed%x
    read (lu,err=999) seed%m_x2c

    ! convert to crystallographic
    r = matinv(seed%m_x2c)
    do i = 1, seed%nat
       seed%x(:,i) = matmul(r,seed%x(:,i))
    end do
    seed%useabr = 2

    errmsg = ""
999 continue
    call fclose(lu)

    ! no symmetry
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = mol
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_pwc

  !> Read the structure from an axsf file (xcrysden). Read the coordinates
  !> from PRIMCOORD block and nudge them using the eigenvector on the same block
  !> scaled by the value of xnudge (bohr).
  module subroutine read_axsf(seed,file,nread0,xnudge,rborder,docube,errmsg)
    use tools_io, only: fopen_read, getline_raw, fclose, lgetword, equal, isinteger, &
       string, getword, isreal, nameguess, zatguess
    use tools_math, only: matinv
    use param, only: bohrtoa
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed !< Crystal seed output
    character*(*), intent(in) :: file !< Input file name
    integer, intent(in) :: nread0
    real*8, intent(in) :: xnudge
    real*8, intent(in) :: rborder !< user-defined border in bohr
    logical, intent(in) :: docube !< if true, make the cell cubic
    character(len=:), allocatable, intent(out) :: errmsg

    character(len=:), allocatable :: line, word, name
    integer :: lu, lp, iprim, i, it, iz, j
    real*8 :: r(3,3), x(3)
    logical :: ok, ismol, didreadr, didreadx
    
    ! open
    ismol = .false.
    errmsg = ""
    lu = fopen_read(file)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if

    errmsg = "Error reading file."
    didreadr = .false.
    didreadx = .false.
    do while (.true.)
       ok = getline_raw(lu,line)
       if (.not.ok) exit
       lp = 1
       word = lgetword(line,lp)
       if (equal(word,"primvec")) then
          didreadr = .true.
          do i = 1, 3
             read (lu,*,err=999) r(i,:)
          end do
          r = r / bohrtoa
          ismol = .false.
       elseif (equal(word,"primcoord")) then
          ok = isinteger(iprim,line,lp)
          if (iprim == nread0) then
             didreadx = .true.
             read (lu,*,err=999) seed%nat
             allocate(seed%x(3,seed%nat),seed%is(seed%nat))
             seed%nspc = 0
             allocate(seed%spc(2))
             do i = 1, seed%nat
                ok = getline_raw(lu,line)
                if (.not.ok) goto 999

                ! read the atomic coordinates
                lp = 1
                ok = isinteger(iz,line,lp)
                if (ok) then
                   ! Z x y z
                   name = nameguess(iz,.true.)
                else
                   word = getword(line,lp)
                   name = trim(adjustl(word))
                   iz = zatguess(name)
                end if
                ok = isreal(seed%x(1,i),line,lp)
                ok = ok.and.isreal(seed%x(2,i),line,lp)
                ok = ok.and.isreal(seed%x(3,i),line,lp)
                if (.not.ok) then
                   errmsg = 'Wrong atomic position.'
                   goto 999
                end if
                seed%x(:,i) = seed%x(:,i) / bohrtoa

                ! file this species if it is a new species
                it = 0
                do j = 1, seed%nspc
                   if (seed%spc(j)%z == iz) then
                      it = j
                      exit
                   end if
                end do
                if (it == 0) then
                   seed%nspc = seed%nspc + 1
                   if (seed%nspc > size(seed%spc,1)) &
                      call realloc(seed%spc,2*seed%nspc)
                   seed%spc(seed%nspc)%z = iz
                   seed%spc(seed%nspc)%name = name
                   it = seed%nspc
                end if
                seed%is(i) = it

                ! read the displacement vector and apply the nudge
                ok = isreal(x(1),line,lp)
                ok = ok.and.isreal(x(2),line,lp)
                ok = ok.and.isreal(x(3),line,lp)
                if (.not.ok) then
                   errmsg = 'Wrong displacement vector.'
                   goto 999
                end if
                seed%x(:,i) = seed%x(:,i) + xnudge * x
             end do
          end if
       end if
    end do
    if (.not.didreadr) then
       errmsg = "Could not find PRIMVEC block "
       goto 999
    end if
    if (.not.didreadx) then
       errmsg = "Could not find PRIMCOORD block number " // string(nread0)
       goto 999
    end if
    call realloc(seed%spc,seed%nspc)
    if (seed%nat == 0) then
       errmsg = "No atoms found."
       goto 999
    end if
    if (seed%nspc == 0) then
       errmsg = "No atomic species found."
       goto 999
    end if

    if (.not.ismol) then
       ! fill the cell metrics
       seed%m_x2c = transpose(r)
       r = matinv(seed%m_x2c)
       seed%useabr = 2

       ! convert atoms to crystallographic
       do i = 1, seed%nat
          seed%x(:,i) = matmul(r,seed%x(:,i))
       end do
    else
       seed%useabr = 0
    end if

    errmsg = ""
999 continue
    call fclose(lu)

    ! symmetry
    seed%havesym = 0
    seed%findsym = -1
    seed%checkrepeats = 0

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = ismol
    seed%cubic = docube
    seed%border = rborder
    seed%havex0 = .false.
    seed%molx0 = 0d0
    seed%file = file
    seed%name = file

  end subroutine read_axsf

  !> Adapt the size of an allocatable 1D type(crystalseed) array
  module subroutine realloc_crystalseed(a,nnew)
    use tools_io, only: ferror, faterr

    type(crystalseed), intent(inout), allocatable :: a(:)
    integer, intent(in) :: nnew

    type(crystalseed), allocatable :: temp(:)
    integer :: l1, u1

    if (.not.allocated(a)) &
       call ferror('realloc_crystalseed','array not allocated',faterr)
    l1 = lbound(a,1)
    u1 = ubound(a,1)
    if (u1 == nnew) return
    allocate(temp(l1:nnew))

    temp(l1:min(nnew,u1)) = a(l1:min(nnew,u1))
    call move_alloc(temp,a)

  end subroutine realloc_crystalseed

  !> Detect the format for the structure-containing file. Normally,
  !> this works by detecting the extension, but the file may be
  !> opened and searched if ambiguity is present. The format and
  !> whether the file contains a molecule or crysatl is returned.
  !> If alsofield is present, then return .true. if the file also
  !> contains a scalar field.
  module subroutine struct_detect_format(file,isformat,ismol,alsofield)
    use param, only: isformat_unknown, isformat_cif, isformat_shelx,&
       isformat_cube, isformat_bincube, isformat_struct, isformat_abinit, isformat_elk,&
       isformat_qein, isformat_qeout, isformat_crystal, isformat_xyz,&
       isformat_wfn, isformat_wfx, isformat_fchk, isformat_molden,&
       isformat_gaussian, isformat_siesta, isformat_xsf, isformat_gen,&
       isformat_vasp, isformat_pwc, isformat_axsf
    use tools_io, only: equal, fopen_read, fclose, lower, getline,&
       getline_raw, equali
    use param, only: dirsep
    character*(*), intent(in) :: file
    integer, intent(out) :: isformat
    logical, intent(out) :: ismol
    logical, intent(out), optional :: alsofield

    character(len=:), allocatable :: basename, wextdot, wext_, line
    logical :: isvasp, alsofield_
    integer :: lu, nat, ios
    character*1 :: isfrac

    if (present(alsofield)) alsofield = .false.
    alsofield_ = .false.
    basename = file(index(file,dirsep,.true.)+1:)
    wextdot = basename(index(basename,'.',.true.)+1:)
    wext_ = basename(index(basename,'_',.true.)+1:)
    isvasp = (index(basename,'CONTCAR') > 0) .or. &
       (index(basename,'CHGCAR') > 0) .or. (index(basename,'CHG') > 0).or.&
       (index(basename,'ELFCAR') > 0) .or. (index(basename,'AECCAR0') > 0).or.&
       (index(basename,'AECCAR2') > 0) .or. (index(basename,'POSCAR') > 0)

    if (equal(wextdot,'cif')) then
       isformat = isformat_cif
       ismol = .false.
    elseif (equal(wextdot,'pwc')) then
       isformat = isformat_pwc
       ismol = .false.
    elseif (equal(wextdot,'res').or.equal(wextdot,'ins')) then
       isformat = isformat_shelx
       ismol = .false.
    elseif (equal(wextdot,'cube')) then
       isformat = isformat_cube
       ismol = .false.
       alsofield_ = .true.
    elseif (equal(wextdot,'bincube')) then
       isformat = isformat_bincube
       ismol = .false.
       alsofield_ = .true.
    elseif (equal(wextdot,'struct')) then
       isformat = isformat_struct
       ismol = .false.
    elseif (equal(wextdot,'DEN').or.equal(wext_,'DEN').or.equal(wextdot,'ELF').or.equal(wext_,'ELF').or.&
       equal(wextdot,'POT').or.equal(wext_,'POT').or.equal(wextdot,'VHA').or.equal(wext_,'VHA').or.&
       equal(wextdot,'VHXC').or.equal(wext_,'VHXC').or.equal(wextdot,'VXC').or.equal(wext_,'VXC').or.&
       equal(wextdot,'GDEN1').or.equal(wext_,'GDEN1').or.equal(wextdot,'GDEN2').or.equal(wext_,'GDEN2').or.&
       equal(wextdot,'GDEN3').or.equal(wext_,'GDEN3').or.equal(wextdot,'LDEN').or.equal(wext_,'LDEN').or.&
       equal(wextdot,'KDEN').or.equal(wext_,'KDEN').or.equal(wextdot,'PAWDEN').or.equal(wext_,'PAWDEN')) then
       isformat = isformat_abinit
       ismol = .false.
       alsofield_ = .true.
    elseif (equal(wextdot,'OUT')) then
       isformat = isformat_elk
       ismol = .false.
    elseif (equal(wextdot,'out')) then
       if (is_espresso(file)) then
          isformat = isformat_qeout
          ismol = .false.
       else
          isformat = isformat_crystal
          ismol = .false.
       end if
    elseif (equal(wextdot,'in')) then
       isformat = isformat_qein
       ismol = .false.
    elseif (equal(wextdot,'xyz')) then
       isformat = isformat_xyz
       ismol = .true.
    elseif (equal(wextdot,'wfn')) then
       isformat = isformat_wfn
       ismol = .true.
       alsofield_ = .true.
    elseif (equal(wextdot,'wfx')) then
       isformat = isformat_wfx
       ismol = .true.
       alsofield_ = .true.
    elseif (equal(wextdot,'log')) then
       isformat = isformat_gaussian
       ismol = .true.
       alsofield_ = .false.
    elseif (equal(wextdot,'fchk')) then
       isformat = isformat_fchk
       ismol = .true.
       alsofield_ = .true.
    elseif (equal(wextdot,'molden')) then
       isformat = isformat_molden
       ismol = .true.
       alsofield_ = .true.
    elseif (equal(wextdot,'STRUCT_OUT').or.equal(wextdot,'STRUCT_IN')) then
       isformat = isformat_siesta
       ismol = .false.
    elseif (equal(wextdot,'xsf')) then
       isformat = isformat_xsf
       ismol = .false.
       lu = fopen_read(file,errstop=.false.)
       if (lu < 0) goto 999
       do while (getline(lu,line))
          if (len_trim(line) > 0) exit
       end do
       if (equali(line,"atoms")) then
          ismol = .true.
       else
          ismol = .false.
       end if
       if (present(alsofield)) then
          do while (getline(lu,line))
             if (equali(line,"begin_block_datagrid_3d")) then
                alsofield_ = .true.
                exit
             end if
          end do
       end if
       call fclose(lu)
       if (.not.present(alsofield)) &
          alsofield_ = .not.ismol
    elseif (equal(wextdot,'gen')) then
       isformat = isformat_gen

       ! determine whether it is a molecule or crystal
       ismol = .false.
       lu = fopen_read(file,errstop=.false.)
       if (lu < 0) goto 999
       do while (getline_raw(lu,line))
          if (len_trim(line) > 0) exit
       end do
       read (line,*,iostat=ios) nat, isfrac
       if (ios /= 0) goto 999
       isfrac = lower(isfrac)
       if (equal(isfrac,"c")) then
          ismol = .true.
       else
          ismol = .false.
       end if
       call fclose(lu)
    elseif (equal(wextdot,'axsf')) then
       isformat = isformat_axsf
       ismol = .false.
    elseif (isvasp) then
       isformat = isformat_vasp
       ismol = .false.
       alsofield_ = (index(basename,'CHGCAR') > 0) .or. (index(basename,'CHG') > 0) .or. &
          (index(basename,'ELFCAR') > 0) .or. (index(basename,'AECCAR0') > 0) .or. &
          (index(basename,'AECCAR2') > 0)
    else
       goto 999
    endif
    if (present(alsofield)) alsofield = alsofield_

    return
999 continue
    isformat = isformat_unknown
    ismol = .false.

  end subroutine struct_detect_format

  !> Read the species into the seed from a VASP POTCAR file.
  module subroutine read_potcar(seed,file,errmsg)
    use tools_io, only: fopen_read, getline_raw, getword, fclose, zatguess
    use types, only: realloc
    class(crystalseed), intent(inout) :: seed !< Output crystal seed
    character*(*), intent(in) :: file !< Input file name
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu, lp
    character(len=:), allocatable :: aux1, aatom, line
    logical :: ok

    errmsg = ""
    seed%nspc = 0
    if (allocated(seed%spc)) deallocate(seed%spc)
    allocate(seed%spc(2))

    ! open
    lu = fopen_read(file,errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening POTCAR file."
       return
    end if

    ! read the atoms
    do while (getline_raw(lu,line))
       lp = 1
       aux1 = getword(line,lp)
       aatom = getword(line,lp)
       seed%nspc = seed%nspc + 1
       if (seed%nspc > size(seed%spc,1)) &
          call realloc(seed%spc,2*seed%nspc)

       seed%spc(seed%nspc)%name = aatom
       seed%spc(seed%nspc)%z = zatguess(aatom)
       line = ""
       do while (.not. (trim(adjustl(line)) == 'End of Dataset'))
          ok = getline_raw(lu,line,.false.)
          if (.not.ok) then
             errmsg = "Unexpected termination of POTCAR file."
             call fclose(lu)
             return
          end if
       end do
    end do
    call realloc(seed%spc,seed%nspc)

    ! close
    call fclose(lu)

  end subroutine read_potcar

  !> Read all seeds from a file. If iafield is present, then
  !> return the seed number for which the file can be read as a 
  !> field (or 0 if none).
  module subroutine read_seeds_from_file(file,mol0,nseed,seed,errmsg,iafield)
    use global, only: rborder_def, doguess
    use tools_io, only: getword, equali
    use param, only: isformat_cube, isformat_bincube, isformat_xyz, isformat_wfn,&
       isformat_wfx, isformat_fchk, isformat_molden, isformat_gaussian,&
       isformat_abinit,isformat_cif,isformat_pwc,&
       isformat_crystal, isformat_elk, isformat_gen, isformat_qein, isformat_qeout,&
       isformat_shelx, isformat_siesta, isformat_struct, isformat_vasp, isformat_xsf, &
       isformat_unknown, dirsep
    character*(*), intent(in) :: file
    integer, intent(in) :: mol0
    integer, intent(out) :: nseed
    type(crystalseed), allocatable, intent(inout) :: seed(:)
    character(len=:), allocatable, intent(out) :: errmsg
    integer, intent(out), optional :: iafield

    character(len=:), allocatable :: path, ofile
    integer :: isformat, mol0_, i
    logical :: ismol, mol, hastypes, alsofield, ok

    errmsg = ""
    alsofield = .false.
    mol0_ = mol0
    nseed = 0
    if (allocated(seed)) deallocate(seed)

    inquire(file=file,exist=ok)
    if (.not.ok) then
       errmsg = "Error opening file."
       goto 999
    end if

    call struct_detect_format(file,isformat,ismol,alsofield)
    if (isformat == isformat_unknown) then
       errmsg = "Unknown file format/extension."
       goto 999
    end if
    if (mol0_ == 1) then
       mol = .true.
    elseif (mol0_ == 0) then
       mol = .false.
    elseif (mol0_ == -1) then
       mol = ismol
    end if

    ! read all available seeds in the file
    if (isformat == isformat_cif) then
       call read_all_cif(nseed,seed,file,mol,errmsg)
    elseif (isformat == isformat_pwc) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_pwc(file,mol,errmsg)
    elseif (isformat == isformat_shelx) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_shelx(file,mol,errmsg)
    elseif (isformat == isformat_shelx) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_shelx(file,mol,errmsg)
    else if (isformat == isformat_cube) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_cube(file,mol,errmsg)
    else if (isformat == isformat_bincube) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_bincube(file,mol,errmsg)
    elseif (isformat == isformat_struct) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_wien(file,mol,errmsg)
    elseif (isformat == isformat_vasp) then
       nseed = 1
       allocate(seed(1))

       ! try to read the types from the file directly
       call seed(1)%read_vasp(file,mol,hastypes,errmsg)

       if (len_trim(errmsg) == 0 .and. .not.hastypes) then
          ! see if we can locate a POTCAR in the same path
          path = file(1:index(file,dirsep,.true.))
          if (len_trim(path) < 1) &
             path = "."
          ofile = trim(path) // "/POTCAR"
          call seed(1)%read_potcar(ofile,errmsg)
          if (len_trim(errmsg) == 0) then
             if (seed(1)%nspc > 0) then
                call seed(1)%read_vasp(file,mol,hastypes,errmsg)
             else
                errmsg = "No atoms found in POTCAR."
             end if
          end if
       end if
    elseif (isformat == isformat_abinit) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_abinit(file,mol,errmsg)
    elseif (isformat == isformat_elk) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_elk(file,mol,errmsg)
    elseif (isformat == isformat_qeout) then
       call read_all_qeout(nseed,seed,file,mol,-1,errmsg)
    elseif (isformat == isformat_crystal) then
       call read_all_crystalout(nseed,seed,file,mol,errmsg)
    elseif (isformat == isformat_qein) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_qein(file,mol,errmsg)
    elseif (isformat == isformat_xyz) then
       call read_all_xyz(nseed,seed,file,errmsg)
    elseif (isformat == isformat_gaussian) then
       call read_all_log(nseed,seed,file,errmsg)
    elseif (isformat == isformat_wfn.or.isformat == isformat_wfx.or.&
       isformat == isformat_fchk.or.isformat == isformat_molden) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_mol(file,isformat,rborder_def,.false.,errmsg)
    elseif (isformat == isformat_siesta) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_siesta(file,mol,errmsg)
    elseif (isformat == isformat_xsf) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_xsf(file,rborder_def,.false.,errmsg)
       if (mol0 /= -1) &
          seed(1)%ismolecule = mol
    elseif (isformat == isformat_gen) then
       nseed = 1
       allocate(seed(1))
       call seed(1)%read_dftbp(file,rborder_def,.false.,errmsg)
       if (mol0 /= -1) &
          seed(1)%ismolecule = mol
    end if

999 continue
    if (len_trim(errmsg) > 0) then
       nseed = 0
       if (allocated(seed)) deallocate(seed)
    end if

    ! handle the doguess option
    do i = 1, nseed
       if (.not.seed(i)%ismolecule) then
          if (doguess == 0) then
             seed(i)%havesym = 0
             seed(i)%findsym = 0
             seed(i)%checkrepeats = 0
          elseif (doguess == 1 .and. seed(i)%havesym == 0) then
             seed(i)%findsym = 1
          else
             seed(i)%findsym = -1
          end if
       end if
    end do

    ! output
    if (present(iafield)) then
       if (alsofield) then
          iafield = 1
       else
          iafield = 0
       end if
    end if

  end subroutine read_seeds_from_file

  !> Define the assignment operator for the crystal seed class.
  module subroutine assign_crystalseed(to,from)
    class(crystalseed), intent(out) :: to
    type(crystalseed), intent(in) :: from

    to%isused = from%isused
    to%file = from%file
    to%name = from%name
    to%nat = from%nat
    if (allocated(from%x)) then
       to%x = from%x
    else
       if (allocated(to%x)) deallocate(to%x)
    end if
    if (allocated(from%is)) then
       to%is = from%is
    else
       if (allocated(to%is)) deallocate(to%is)
    end if
    to%nspc = from%nspc
    if (allocated(from%spc)) then
       to%spc = from%spc
    else
       if (allocated(to%spc)) deallocate(to%spc)
    end if
    to%useabr = from%useabr
    to%aa = from%aa
    to%bb = from%bb
    to%m_x2c = from%m_x2c
    to%havesym = from%havesym
    to%findsym = from%findsym
    to%checkrepeats = from%checkrepeats
    to%neqv = from%neqv
    to%ncv = from%ncv
    if (allocated(from%cen)) then
       to%cen = from%cen
    else
       if (allocated(to%cen)) deallocate(to%cen)
    end if
    if (allocated(from%rotm)) then
       to%rotm = from%rotm
    else
       if (allocated(to%rotm)) deallocate(to%rotm)
    end if
    to%ismolecule = from%ismolecule
    to%cubic = from%cubic
    to%border = from%border
    to%havex0 = from%havex0
    to%molx0 = from%molx0

  end subroutine assign_crystalseed

  !xx! private subroutines

  !> Read all structures from a CIF file (uses ciftbx) and returns all
  !> crystal seeds.
  subroutine read_all_cif(nseed,seed,file,mol,errmsg)
    use arithmetic, only: eval, isvariable, setvariable
    use global, only: critic_home
    use tools_io, only: falloc, uout, lower, zatguess, fdealloc, nameguess
    use param, only: dirsep
    use types, only: realloc

    include 'ciftbx/ciftbx.cmv'
    include 'ciftbx/ciftbx.cmf'

    integer, intent(out) :: nseed !< number of seeds
    type(crystalseed), intent(inout), allocatable :: seed(:) !< seeds on output
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< Is this a molecule? 
    character(len=:), allocatable, intent(out) :: errmsg

    character(len=1024) :: dictfile
    logical :: fl
    integer :: ludum, luscr

    errmsg = ""
    nseed = 0
    if (allocated(seed)) deallocate(seed)
    ludum = falloc()
    luscr = falloc()
    fl = init_(ludum, uout, luscr, uout)
    if (.not.checkcifop()) goto 999

    ! open dictionary
    dictfile = trim(adjustl(critic_home)) // dirsep // "cif" // dirsep // 'cif_core.dic'
    fl = dict_(dictfile,'valid')
    if (.not.checkcifop()) goto 999
    if (.not.fl) then
       errmsg = "Dictionary file (cif_core.dic) not found."
       goto 999
    end if

    ! open cif file
    fl = ocif_(file)
    if (.not.checkcifop()) goto 999
    if (.not.fl) then
       errmsg = "Error opening file."
       goto 999
    end if

    allocate(seed(1))
    ! read data blocks
    do while (data_(" "))
       nseed = nseed + 1
       if (nseed > size(seed,1)) call realloc_crystalseed(seed,2*nseed)

       seed(nseed)%file = file
       seed(nseed)%name = file

       call read_cif_items(seed(nseed),mol,errmsg)
       if (len_trim(errmsg) > 0) then
          if (allocated(seed)) deallocate(seed)
          nseed = 0
          goto 999
       end if
    end do
    call realloc_crystalseed(seed,nseed)       

999 continue

    ! clean up
    call purge_()
    call fdealloc(ludum)
    call fdealloc(luscr)

  contains
    function checkcifop()
      use tools_io, only: string
      logical :: checkcifop
      checkcifop = (cifelin_ == 0)
      if (checkcifop) then
         errmsg = ""
      else
         errmsg = trim(cifemsg_) // " (Line: " // string(cifelin_) // ")"
      end if
    end function checkcifop
  end subroutine read_all_cif

  !> Read one or all structures from a QE output (filename file) and
  !> return the corresponding crystal seeds in seed. If istruct < 0,
  !> read all seeds and return the number of seeds read in nseed.  The
  !> first seed is a repeat of the last. If istruct = 0, return a
  !> single seed for the last structure. If istruct > 0, return that
  !> particular structure. If mol=.true., interpret the structure as a
  !> molecule (currently, this only sets the %ismolecule field). If
  !> an error condition is found, return the error message in errmsg
  !> (zero-length string if no error).
  subroutine read_all_qeout(nseed,seed,file,mol,istruct,errmsg)
    use tools_io, only: fopen_read, getline_raw, isinteger, isreal,&
       zatguess, fclose, equali, string
    use tools_math, only: matinv
    use param, only: bohrtoa
    use types, only: realloc, species
    integer, intent(out) :: nseed !< number of seeds
    type(crystalseed), intent(inout), allocatable :: seed(:) !< seeds on output
    character*(*), intent(in) :: file !< Input file name
    integer, intent(in) :: istruct !< ID of the structure
    logical, intent(in) :: mol !< Is this a molecule? 
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu, ideq, i, j, is0
    character(len=:), allocatable :: line
    character*10 :: atn, sdum
    character*40 :: sene
    integer :: idum
    real*8 :: alat, r(3,3), qaux, rfac, cfac, rdum
    logical :: ok, tox
    ! interim copy of seed info
    integer :: nat, nspc, iuse
    real*8, allocatable :: x(:,:)
    integer, allocatable :: is(:)
    type(species), allocatable :: spc(:) !< Species
    real*8 :: m_x2c(3,3)
    logical :: hasx, hasis, hasspc, hasr

    errmsg = ""
    lu = fopen_read(file,errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if

    ! first pass: read the number of structures
    nseed = 0
    do while (getline_raw(lu,line))
       if (index(line,"!") == 1) then
          nseed = nseed + 1
       end if
    end do
    if (nseed == 0) then
       errmsg = "No valid structures found."
       goto 999
    end if
    if (allocated(seed)) deallocate(seed)

    if (istruct >= 0) then
       is0 = 0
       allocate(seed(1))
       seed(1)%nspc = 0
       seed(1)%nat = 0
    else
       if (nseed > 1) then
          nseed = nseed + 1
          is0 = 1
       else
          nseed = 1
          is0 = 0
       end if
       allocate(seed(nseed))
       do i = 1, nseed
          seed(i)%nspc = 0
          seed(i)%nat = 0
       end do
    end if
    alat = 1d0

    ! rewind and read all the structures
    rewind(lu)
    errmsg = "Error reading file."
    nat = 0
    nspc = 0
    tox = .false.
    hasx = .false.
    hasis = .false.
    hasspc = .false.
    hasr = .false.
    do while (getline_raw(lu,line))
       ideq = index(line,"=") + 1

       ! Count the structures
       if (index(line,"lattice parameter (alat)") > 0) then
          ok = isreal(alat,line,ideq)

       elseif (index(line,"number of atoms/cell") > 0) then
          ok = isinteger(nat,line,ideq)
          if (allocated(x)) deallocate(x)
          if (allocated(is)) deallocate(is)
          allocate(x(3,nat),is(nat))

       elseif (index(line,"number of atomic types") > 0) then
          ok = isinteger(nspc,line,ideq)
          if (allocated(spc)) deallocate(spc)
          allocate(spc(nspc))

       elseif (index(line,"atomic species   valence    mass     pseudopotential")>0) then
          do i = 1, nspc
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
             read (line,*,err=999) spc(i)%name, qaux
             spc(i)%z = zatguess(spc(i)%name)
             if (spc(i)%z < 0) then
                errmsg = "Unknown atomic symbol: "//trim(spc(i)%name)//"."
                goto 999
             end if
          end do
          hasspc = .true.

       elseif (index(line,"crystal axes:") > 0) then
          do i = 1, 3
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
             ideq = index(line,"(",.true.) + 1
             ok = isreal(r(i,1),line,ideq)
             ok = ok.and.isreal(r(i,2),line,ideq)
             ok = ok.and.isreal(r(i,3),line,ideq)
             if (.not.ok) goto 999
          end do
          r = r * alat ! alat comes before crystal axes
          m_x2c = transpose(r)
          tox = .false.
          hasr = .true.

       elseif (index(line,"Cartesian axes")>0) then
          ok = getline_raw(lu,line)
          if (.not.ok) goto 999
          ok = getline_raw(lu,line)
          if (.not.ok) goto 999
          is = 0
          do i = 1, nat
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
             read(line,*,err=999) idum, atn
             line = line(index(line,"(",.true.)+1:)
             read(line,*,err=999) x(:,i)
             do j = 1, nspc
                if (equali(spc(j)%name,atn)) then
                   is(i) = j
                   exit
                end if
             end do
             if (is(i) == 0) then
                errmsg = "Unknown atom type: "//atn
                goto 999
             end if
          end do
          ! this is Cartesian in alat units
          x = x * alat
          tox = .true.
          hasx = .true.
          hasis = .true.

       elseif (line(1:15) == "CELL_PARAMETERS") then
          cfac = 1d0
          if (index(line,"angstrom") > 0) then
             cfac = 1d0 / bohrtoa 
          elseif (index(line,"alat") > 0) then
             cfac = alat
          elseif (index(line,"bohr") > 0) then
             cfac = 1d0
          end if
          do i = 1, 3
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
             ideq = 1
             ok = isreal(r(i,1),line,ideq)
             ok = ok.and.isreal(r(i,2),line,ideq)
             ok = ok.and.isreal(r(i,3),line,ideq)
             if (.not.ok) goto 999
          end do
          r = r * cfac
          m_x2c = transpose(r)
          hasr = .true.

       elseif (line(1:16) == "ATOMIC_POSITIONS") then
          rfac = 1d0
          if (index(line,"angstrom") > 0) then
             tox = .true.
             rfac = 1d0 / bohrtoa 
          elseif (index(line,"alat") > 0) then
             tox = .true.
             rfac = alat
          elseif (index(line,"bohr") > 0) then
             tox = .true.
             rfac = 1d0
          elseif (index(line,"crystal") > 0) then
             tox = .false.
             rfac = 1d0
          end if
          is = 0
          do i = 1, nat
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
             read(line,*,err=999) atn, x(:,i)
             do j = 1, nspc
                if (equali(spc(j)%name,atn)) then
                   is(i) = j
                   exit
                end if
             end do
             if (is(i) == 0) then
                errmsg = "Unknown atom type: "//atn
                goto 999
             end if
          end do
          x = x * rfac
          hasx = .true.
       else if (index(line,"!") == 1) then
          if (.not.hasx .or. nat == 0) then
             errmsg = "Missing atomic positions."
             goto 999
          end if
          if (.not.hasis) then
             errmsg = "Missing atomic types."
             goto 999
          end if
          if (.not.hasspc .or. nspc == 0) then
             errmsg = "Missing atomic species."
             goto 999
          end if
          if (.not.hasr) then
             errmsg = "Missing cell dimensions."
             goto 999
          end if
          is0 = is0 + 1
          hasx = .false.

          ! decide whether we want to keep this structure in a seed
          iuse = 0
          if (istruct < 0) then
             iuse = is0
          elseif (istruct == 0 .and. is0 == nseed) then
             iuse = 1
          elseif (istruct == is0) then
             iuse = 1
          end if
          
          ! keep the seed
          if (iuse > 0) then
             seed(iuse)%nat = nat
             seed(iuse)%nspc = nspc
             seed(iuse)%spc = spc
             seed(iuse)%x = x
             seed(iuse)%is = is
             seed(iuse)%m_x2c = m_x2c

             seed(iuse)%useabr = 2
             r = matinv(seed(iuse)%m_x2c)
             do i = 1, seed(iuse)%nat
                if (tox) then
                   seed(iuse)%x(:,i) = matmul(r,seed(iuse)%x(:,i))
                end if
                seed(iuse)%x(:,i) = seed(iuse)%x(:,i) - floor(seed(iuse)%x(:,i))
             end do

             seed(iuse)%havesym = 0
             seed(iuse)%checkrepeats = 0
             seed(iuse)%findsym = -1
             seed(iuse)%isused = .true.
             seed(iuse)%ismolecule = mol
             seed(iuse)%cubic = .false.
             seed(iuse)%border = 0d0
             seed(iuse)%havex0 = .false.
             seed(iuse)%molx0 = 0d0
             seed(iuse)%file = file

             read (line,*,err=999) sdum, sdum, sdum, sdum, sene
             read (sene,*,err=999) rdum
             seed(iuse)%name = trim(adjustl(string(rdum,'f',20,8))) // " Ry"
          end if
       end if
    end do

    if (istruct >= 0) then
       nseed = 1
    else if (nseed > 1) then
       seed(1) = seed(nseed)
       seed(1)%name = "(final) " // trim(seed(1)%name)
       seed(2)%name = "(initial) " // trim(seed(2)%name)
    end if

    errmsg = ""
999 continue
    call fclose(lu)
    if (len_trim(errmsg) > 0) then
       nseed = 0
       if (allocated(seed)) deallocate(seed)
    end if

  end subroutine read_all_qeout

  !> Read all structures from a QE outupt. Returns all crystal seeds.
  subroutine read_all_crystalout(nseed,seed,file,mol,errmsg)
    use tools_math, only: m_x2c_from_cellpar, matinv, det
    use tools_io, only: fopen_read, fclose, getline_raw, string
    use types, only: realloc
    use param, only: maxzat0, bohrtoa
    integer, intent(out) :: nseed !< number of seeds
    type(crystalseed), intent(inout), allocatable :: seed(:) !< seeds on output
    character*(*), intent(in) :: file !< Input file name
    logical, intent(in) :: mol !< Is this a molecule? 
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu, i, is0
    character(len=:), allocatable :: line
    character*10 :: sdum, atn
    character*40 :: sene
    integer :: idum, iz, isz(maxzat0), idx
    real*8 :: rdum, r(3,3), rtrans(3,3), dd
    logical :: ok
    ! interim copy of seed info
    integer :: nat, nspc
    real*8, allocatable :: x(:,:)
    integer, allocatable :: is(:)
    type(species), allocatable :: spc(:)
    real*8 :: aa(3), bb(3)
    logical :: hasx, hasr, hasab, hastrans

    errmsg = ""
    lu = fopen_read(file,errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if

    ! first pass: read opt status and number of structures
    nseed = 0
    if (allocated(seed)) deallocate(seed)
    do while (getline_raw(lu,line))
       if (index(line,"COORDINATE AND CELL OPTIMIZATION - POINT") > 0) then
          nseed = nseed + 1
       end if
    end do
    if (nseed == 0) then
       ! This is a single-point calculation. Use the one-reader.
       call fclose(lu)
       nseed = 1
       allocate(seed(nseed))
       call seed(1)%read_crystalout(file,mol,errmsg)
       return
    end if

    nseed = nseed + 1
    is0 = 1
    allocate(seed(nseed))
    do i = 1, nseed
       seed(i)%nspc = 0
       seed(i)%nat = 0
    end do
    allocate(spc(10))

    ! rewind and read all the structures
    rewind(lu)
    errmsg = "Error reading file."
    isz = 0
    nat = 0
    nspc = 0
    hasx = .false.
    hasr = .false.
    hasab = .false.
    hastrans = .false.
    do while (getline_raw(lu,line))

       if (index(line,"DIRECT LATTICE VECTORS CARTESIAN COMPONENTS") > 0) then
          if (hastrans) cycle
          ok = getline_raw(lu,line)
          if (.not.ok) goto 999
          do i = 1, 3
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
             read (line,*,err=999) r(i,:)
          end do
          r = transpose(r) / bohrtoa
          hasr = .true.
          if (.not.hasab) then
             errmsg = "Invalid cell dimensions"
             goto 999
          end if

          rtrans = m_x2c_from_cellpar(aa,bb)
          rtrans = matinv(rtrans) * r
          dd = abs(det(rtrans))
          if (abs(dd - 1d0) > 1d-10) then
             errmsg = "Invalid transformation matrix"
             goto 999
          end if
          hastrans = .true.
          hasr = .true.

       elseif (index(line,"LATTICE PARAMETERS (ANGSTROMS AND DEGREES)") > 0) then
          ok = getline_raw(lu,line)
          ok = ok.and.getline_raw(lu,line)
          ok = ok.and.getline_raw(lu,line)
          if (.not.ok) goto 999
          read (line,*,err=999) aa, bb
          aa = aa / bohrtoa
          if (hastrans) then
             r = m_x2c_from_cellpar(aa,bb) * rtrans
             hasr = .true.
          end if
          hasab = .true.

       elseif (index(line,"ATOMS IN THE UNIT CELL") > 0) then
          if (nat == 0) then
             read (line,*,err=999) (sdum,i=1,12), nat
             if (allocated(x)) deallocate(x)
             if (allocated(is)) deallocate(is)
             allocate(x(3,nat),is(nat))
          end if
          ok = getline_raw(lu,line)
          ok = ok.and.getline_raw(lu,line)
          if (.not.ok) goto 999

          do i = 1, nat
             ok = getline_raw(lu,line)
             if (.not.ok) goto 999
             read (line,*,err=999) idum, sdum, iz, atn, x(:,i)

             iz = mod(iz,200)
             if (isz(iz) == 0) then
                nspc = nspc + 1
                if (nspc > size(spc,1)) &
                   call realloc(spc,2*nspc)
                spc(nspc)%name = trim(adjustl(atn))
                spc(nspc)%z = iz
                spc(nspc)%qat = 0d0
                isz(iz) = nspc
             end if
             is(i) = isz(iz)
          end do
          hasx = .true.

       else if (index(line,"TOTAL ENERGY(") > 0) then
          if (.not.hasx .or. nat == 0) then
             errmsg = "Missing atomic positions."
             goto 999
          end if
          if (nspc == 0) then
             errmsg = "Missing atomic species."
             goto 999
          end if
          if (.not.hasr.or..not.hasab) then
             errmsg = "Missing cell dimensions."
             goto 999
          end if
          if (.not.hastrans) then
             errmsg = "Missing cell transformation."
             goto 999
          end if

          do i = 1, 3
             idx = index(line,")")
             if (idx == 0) goto 999
             line = line(idx+1:)
          end do
          read (line,*,err=999) sene
          is0 = is0 + 1
          hasr = .false.
          hasab = .false.
          hasx = .false.

          seed(is0)%m_x2c = r
          r = matinv(r)
          seed(is0)%useabr = 2

          seed(is0)%nat = nat
          seed(is0)%nspc = nspc
          seed(is0)%spc = spc
          allocate(seed(is0)%x(size(x,1),size(x,2)))
          do i = 1, nat
             seed(is0)%x(:,i) = matmul(r,x(:,i) * aa)
             seed(is0)%x(:,i) = seed(is0)%x(:,i) - floor(seed(is0)%x(:,i))
          end do
          seed(is0)%is = is

          seed(is0)%havesym = 0
          seed(is0)%checkrepeats = 0
          seed(is0)%findsym = -1
          seed(is0)%isused = .true.
          seed(is0)%ismolecule = mol
          seed(is0)%cubic = .false.
          seed(is0)%border = 0d0
          seed(is0)%havex0 = .false.
          seed(is0)%molx0 = 0d0
          seed(is0)%file = file
          read (sene,*,err=999) rdum
          seed(is0)%name = trim(adjustl(string(rdum,'f',20,8))) // " Ha"
       end if
    end do

    seed(1) = seed(nseed)
    seed(1)%name = "(final) " // trim(seed(1)%name)
    seed(2)%name = "(initial) " // trim(seed(2)%name)

    errmsg = ""
999 continue
    call fclose(lu)
    if (len_trim(errmsg) > 0) then
       nseed = 0
       if (allocated(seed)) deallocate(seed)
    end if

  end subroutine read_all_crystalout

  !> Read all structures from an xyz file. Returns all crystal seeds.
  subroutine read_all_xyz(nseed,seed,file,errmsg)
    use global, only: rborder_def
    use hashmod, only: hash
    use tools_io, only: fopen_read, fclose, getline_raw, lower, zatguess,&
       isinteger, string, nameguess
    use types, only: realloc
    use param, only: maxzat, bohrtoa
    integer, intent(out) :: nseed !< number of seeds
    type(crystalseed), intent(inout), allocatable :: seed(:) !< seeds on output
    character*(*), intent(in) :: file !< Input file name
    character(len=:), allocatable, intent(out) :: errmsg

    integer :: lu, nat, i, iz
    logical :: ok
    character(len=:), allocatable :: line, latn
    character*10 :: atn
    type(hash) :: usen

    errmsg = ""
    lu = fopen_read(file,errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if

    errmsg = "Error reading file."
    nseed = 0
    do while (getline_raw(lu,line))
       if (len_trim(line) == 0) cycle
       read (line,*,err=999) nat
       ok = getline_raw(lu,line)
       if (.not.ok) goto 999
       do i = 1, nat
          ok = getline_raw(lu,line)
          if (.not.ok) goto 999
       end do
       nseed = nseed + 1
    end do

    if (allocated(seed)) deallocate (seed)
    allocate(seed(nseed))
    rewind(lu)
    nseed = 0
    do while (getline_raw(lu,line))
       if (len_trim(line) == 0) cycle
       nseed = nseed + 1
       call usen%init()
       read (line,*,err=999) nat
       seed(nseed)%nat = nat

       ok = getline_raw(lu,line)
       if (.not.ok) goto 999
       seed(nseed)%file = file
       if (len_trim(line) > 0) then
          seed(nseed)%name = trim(adjustl(line))
       else
          seed(nseed)%name = seed(nseed)%file
       end if

       seed(nseed)%nspc = 0
       allocate(seed(nseed)%x(3,nat),seed(nseed)%is(nat),seed(nseed)%spc(10))
       do i = 1, nat
          read (lu,*,err=999) atn, seed(nseed)%x(:,i)

          ok = isinteger(iz,atn)
          if (ok) then
             if (iz < 0 .or. iz > maxzat) then
                errmsg = "Invalid atomic number: "//string(iz)//"."
                goto 999
             end if
             atn = nameguess(iz,.true.)
          else
             iz = zatguess(atn)
             if (iz < 0) then
                errmsg = "Unknown atomic symbol: "//trim(atn)//"."
                goto 999
             end if
          end if

          latn = lower(trim(atn))
          if (usen%iskey(latn)) then
             seed(nseed)%is(i) = usen%get(latn,1)
          else
             seed(nseed)%nspc = seed(nseed)%nspc + 1
             if (seed(nseed)%nspc > size(seed(nseed)%spc,1)) &
                call realloc(seed(nseed)%spc,2*seed(nseed)%nspc)
             seed(nseed)%spc(seed(nseed)%nspc)%name = trim(atn)
             seed(nseed)%spc(seed(nseed)%nspc)%z = iz
             seed(nseed)%spc(seed(nseed)%nspc)%qat = 0d0
             call usen%put(latn,seed(nseed)%nspc)
             seed(nseed)%is(i) = seed(nseed)%nspc
          end if
       end do
       call realloc(seed(nseed)%spc,seed(nseed)%nspc)
       seed(nseed)%x = seed(nseed)%x / bohrtoa
       seed(nseed)%useabr = 0
       seed(nseed)%havesym = 0
       seed(nseed)%checkrepeats = 0
       seed(nseed)%findsym = -1
       seed(nseed)%isused = .true.
       seed(nseed)%ismolecule = .true.
       seed(nseed)%cubic = .false.
       seed(nseed)%border = rborder_def
       seed(nseed)%havex0 = .false.
       seed(nseed)%molx0 = 0d0
    end do

    errmsg = ""
999 continue
    call fclose(lu)
    if (len_trim(errmsg) > 0) then
       nseed = 0
       if (allocated(seed)) deallocate(seed)
    end if

  end subroutine read_all_xyz

  !> Read all structures from a Gaussian output (log) file. Returns
  !> all crystal seeds.
  subroutine read_all_log(nseed,seed,file,errmsg)
    use global, only: rborder_def
    use tools_io, only: fopen_read, fclose, getline_raw, nameguess
    use types, only: species
    use param, only: maxzat, bohrtoa
    integer, intent(out) :: nseed !< number of seeds
    type(crystalseed), intent(inout), allocatable :: seed(:) !< seeds on output
    character*(*), intent(in) :: file !< Input file name
    character(len=:), allocatable, intent(out) :: errmsg

    character(len=:), allocatable :: line
    character*64 :: word
    integer :: lu, nat, idum, iz, nspc, i
    integer :: usez(0:maxzat), idx, in
    logical :: ok, laste
    type(species), allocatable :: spc(:)

    errmsg = ""

    lu = fopen_read(file,errstop=.false.)
    if (lu < 0) then
       errmsg = "Error opening file."
       return
    end if
    errmsg = "Error reading file."

    ! count the number of seeds, atoms, and build the species
    nat = 0
    nseed = 0
    do while (getline_raw(lu,line))
       if (index(line,"Input orientation:") > 0) then
          nseed = nseed + 1

          if (nat == 0) then
             usez = 0
             ok = getline_raw(lu,line)
             ok = ok .and. getline_raw(lu,line)
             ok = ok .and. getline_raw(lu,line)
             ok = ok .and. getline_raw(lu,line)
             if (.not.ok) goto 999
             do while (.true.)
                ok = getline_raw(lu,line)
                if (.not.ok) goto 999
                if (index(line,"---------") > 0) exit
                nat = nat + 1
                read(line,*,err=999) idum, iz
                usez(iz) = 1
             end do
          end if
       end if
    end do
    if (nat == 0) then
       errmsg = "No atoms found."
       goto 999
    end if

    ! build the species
    nspc = count(usez > 0)
    if (nspc == 0) then
       errmsg = "No species found."
       goto 999
    end if
    allocate(spc(nspc))
    nspc = 0
    do i = 0, maxzat
       if (usez(i) > 0) then
          nspc = nspc + 1
          spc(nspc)%z = i
          spc(nspc)%name = nameguess(i,.true.)
          spc(nspc)%qat = 0d0
          usez(i) = nspc
       end if
    end do

    if (allocated(seed)) deallocate(seed)
    allocate(seed(nseed))
    rewind(lu)
    in = 1
    do while (getline_raw(lu,line))
       if (index(line,"Input orientation:") > 0) then
          in = mod(in,nseed) + 1
          seed%nat = nat
          allocate(seed(in)%x(3,nat),seed(in)%is(nat))

          ok = getline_raw(lu,line)
          ok = ok .and. getline_raw(lu,line)
          ok = ok .and. getline_raw(lu,line)
          ok = ok .and. getline_raw(lu,line)
          if (.not.ok) goto 999

          do i = 1, nat
             read (lu,*,err=999) idum, iz, idum, seed(in)%x(:,i)
             seed(in)%is(i) = usez(iz)
          end do

          seed(in)%x = seed(in)%x / bohrtoa
          seed(in)%isused = .true.
          seed(in)%file = file
          seed(in)%name = file
          seed(in)%nspc = nspc
          seed(in)%spc = spc
          seed(in)%useabr = 0
          seed(in)%havesym = 0
          seed(in)%checkrepeats = 0
          seed(in)%findsym = -1
          seed(in)%isused = .true.
          seed(in)%ismolecule = .true.
          seed(in)%cubic = .false.
          seed(in)%border = rborder_def
          seed(in)%havex0 = .false.
          seed(in)%molx0 = 0d0
          laste = .false.
       elseif (index(line,"SCF Done") > 0) then
          idx = index(line,"=")
          if (idx > 0) then
             line = line(idx+1:)
             read (line,*) word
             seed(in)%name = trim(adjustl(word))
          end if
          laste = .true.
       end if
    end do
    if (.not.laste .and. nseed > 1) then
       seed(1)%name = "(final) " // trim(seed(nseed)%name)
       seed(2)%name = "(initial) " // trim(seed(2)%name)
    end if

    errmsg = ""
999 continue
    call fclose(lu)
    if (len_trim(errmsg) > 0) then
       nseed = 0
       if (allocated(seed)) deallocate(seed)
    end if

  end subroutine read_all_log

  !> Read all items in a cif file when the cursor has already been
  !> moved to the corresponding data block. Fills seed.
  subroutine read_cif_items(seed,mol,errmsg)
    use arithmetic, only: eval, isvariable, setvariable
    use param, only: bohrtoa
    use tools_io, only: lower, zatguess, nameguess
    use param, only: bohrtoa, eye, eyet
    use types, only: realloc

    include 'ciftbx/ciftbx.cmv'
    include 'ciftbx/ciftbx.cmf'

    type(crystalseed), intent(inout) :: seed
    logical, intent(in) :: mol
    character(len=:), allocatable, intent(out) :: errmsg

    character(len=1024) :: sym, tok
    character*30 :: atname, spg
    integer :: i, j, it, iznum, idx
    logical :: found, fl, ix, iy, iz, fl1, fl2, ok, iok
    real*8 :: sigx, rot0(3,4), x(3), xo, yo, zo

    character*(1), parameter :: ico(3) = (/"x","y","z"/)

    ix = .false.
    iy = .false.
    iz = .false.
    errmsg = ""

    if (len_trim(bloc_) > 0) &
       seed%name = trim(bloc_)

    ! read cell dimensions
    seed%useabr = 1
    fl = numd_('_cell_length_a',seed%aa(1),sigx)
    if (.not.checkcifop()) goto 999
    fl = fl .and. numd_('_cell_length_b',seed%aa(2),sigx)
    if (.not.checkcifop()) goto 999
    fl = fl .and. numd_('_cell_length_c',seed%aa(3),sigx)
    if (.not.checkcifop()) goto 999
    if (.not.fl) then
       errmsg = "Error readinig cell lengths."
       return
    end if
    seed%aa = seed%aa / bohrtoa

    ! read cell angles
    fl = numd_('_cell_angle_alpha',seed%bb(1),sigx)
    if (.not.checkcifop()) goto 999
    fl = fl .and. numd_('_cell_angle_beta',seed%bb(2),sigx)
    if (.not.checkcifop()) goto 999
    fl = fl .and. numd_('_cell_angle_gamma',seed%bb(3),sigx)
    if (.not.checkcifop()) goto 999
    if (.not.fl) then
       errmsg = "Error readinig cell angles."
       return
    end if

    ! read atomic positions
    seed%nat = 1
    seed%nspc = 0
    allocate(seed%spc(1))
    allocate(seed%x(3,10),seed%is(10))
    do while(.true.)
       if (seed%nat > size(seed%is)) then
          call realloc(seed%is,2*seed%nat)
          call realloc(seed%x,3,2*seed%nat)
       end if
       atname = ""
       fl = char_('_atom_site_type_symbol',atname)
       if (.not.checkcifop()) goto 999
       if (.not.fl) then
          fl = char_('_atom_site_label',atname)
          if (.not.checkcifop()) goto 999
       end if
       iznum = zatguess(atname)
       if (iznum < 0) then
          errmsg = "Unknown atomic symbol: "//trim(atname)//"."
          return
       end if

       found = .false.
       do i = 1, seed%nspc
          if (seed%spc(i)%z == iznum) then
             it = i
             found = .true.
             exit
          end if
       end do
       if (.not.found) then
          seed%nspc = seed%nspc + 1
          if (seed%nspc > size(seed%spc,1)) &
             call realloc(seed%spc,2*seed%nspc)
          seed%spc(seed%nspc)%z = iznum
          seed%spc(seed%nspc)%name = nameguess(iznum,.true.)
          it = seed%nspc
       end if
       seed%is(seed%nat) = it

       fl = fl .and. numd_('_atom_site_fract_x',x(1),sigx)
       if (.not.checkcifop()) goto 999
       fl = fl .and. numd_('_atom_site_fract_y',x(2),sigx)
       if (.not.checkcifop()) goto 999
       fl = fl .and. numd_('_atom_site_fract_z',x(3),sigx)
       if (.not.checkcifop()) goto 999
       seed%x(:,seed%nat) = x
       if (.not.fl) then
          errmsg = "Error reading atomic positions."
          return
       end if
       if (.not.loop_) exit
       seed%nat = seed%nat + 1
    end do
    call realloc(seed%spc,seed%nspc)
    call realloc(seed%is,seed%nat)
    call realloc(seed%x,3,seed%nat)

    ! save the old value of x, y, and z variables
    ix = isvariable("x",xo)
    iy = isvariable("y",yo)
    iz = isvariable("z",zo)

    ! use the symmetry information from _symmetry_equiv_pos_as_xyz
    found = .false.
    fl1 = .false.
    fl2 = .false.
    seed%neqv = 0
    seed%ncv = 1
    if (.not.allocated(seed%cen)) allocate(seed%cen(3,4))
    seed%cen(:,1) = 0d0
    if (.not.allocated(seed%rotm)) allocate(seed%rotm(3,4,48))
    seed%rotm = 0d0
    seed%rotm(:,:,1) = eyet
    do while(.true.)
       if (.not.found) then
          fl1 = char_('_symmetry_equiv_pos_as_xyz',sym)
          if (.not.checkcifop()) goto 999
          if (.not.fl1) then
             fl2 = char_('_space_group_symop_operation_xyz',sym)
             if (.not.checkcifop()) goto 999
          end if
          if (.not.(fl1.or.fl2)) exit
          found = .true.
       else
          if (fl1) then
             fl1 = char_('_symmetry_equiv_pos_as_xyz',sym)
             if (.not.checkcifop()) goto 999
          end if
          if (fl2) then
             fl2 = char_('_space_group_symop_operation_xyz',sym)
             if (.not.checkcifop()) goto 999
          end if
       endif

       ! do stuff with sym
       if (.not.(fl1.or.fl2)) then
          errmsg = "Error reading symmetry xyz elements."
          goto 999
       end if

       ! process the three symmetry elements
       rot0 = 0d0
       sym = trim(adjustl(lower(sym))) // ","
       do i = 1, 3
          ! extract the next token
          idx = index(sym,",")
          if (idx == 0) then
             errmsg = "Error reading symmetry operation."
             goto 999
          end if
          tok = sym(1:idx-1)
          sym = sym(idx+1:)

          ! the translation component
          do j = 1, 3
             call setvariable(ico(j),0d0)
          end do
          rot0(i,4) = eval(tok,.false.,iok)
          if (.not.iok) then
             errmsg = "Error evaluating expression: " // trim(tok)
             goto 999
          end if

          ! the x-, y-, z- components
          do j = 1, 3
             call setvariable(ico(j),1d0)
             rot0(i,j) = eval(tok,.false.,iok) - rot0(i,4)
             if (.not.iok) then
                errmsg = "Error evaluating expression: " // trim(tok)
                goto 999
             end if
             call setvariable(ico(j),0d0)
          enddo
       enddo

       ! now we have a rot0
       if (all(abs(eyet - rot0) < 1d-12)) then
          ! the identity
          seed%neqv = seed%neqv + 1
          if (seed%neqv > size(seed%rotm,3)) &
             call realloc(seed%rotm,3,4,2*seed%neqv)
          seed%rotm(:,:,seed%neqv) = rot0
       elseif (all(abs(eye - rot0(1:3,1:3)) < 1d-12)) then
          ! a non-zero pure translation
          ! check if I have it already
          ok = .true.
          do i = 1, seed%ncv
             if (all(abs(rot0(:,4) - seed%cen(:,i)) < 1d-12)) then
                ok = .false.
                exit
             endif
          end do
          if (ok) then
             seed%ncv = seed%ncv + 1
             if (seed%ncv > size(seed%cen,2)) call realloc(seed%cen,3,2*seed%ncv)
             seed%cen(:,seed%ncv) = rot0(:,4)
          endif
       else
          ! a rotation, with some pure translation in it
          ! check if I have this rotation matrix already
          ok = .true.
          do i = 1, seed%neqv
             if (all(abs(seed%rotm(1:3,1:3,i) - rot0(1:3,1:3)) < 1d-12)) then
                ok = .false.
                exit
             endif
          end do
          if (ok) then
             seed%neqv = seed%neqv + 1
             seed%rotm(:,:,seed%neqv) = rot0
          endif
       endif
       ! exit the loop
       if (.not.loop_) exit
    end do

    seed%havesym = 1
    seed%checkrepeats = 1
    seed%findsym = 0
    if (seed%neqv == 0) then
       seed%neqv = 1
       seed%rotm(:,:,1) = eyet
       seed%rotm = 0d0
       seed%havesym = 0
       seed%checkrepeats = 0
       seed%findsym = -1
    end if
    call realloc(seed%rotm,3,4,seed%neqv)
    call realloc(seed%cen,3,seed%ncv)

    ! read and process spg information
    if (.not.found) then
       ! the "official" Hermann-Mauginn symbol from the dictionary: many cif files don't have one
       fl = char_('_symmetry_space_group_name_H-M',spg)
       if (.not.checkcifop()) goto 999

       ! the "alternative" symbol... the core dictionary says I shouldn't be using this
       if (.not.fl) fl = char_('_space_group_name_H-M_alt',spg)
       if (.not.checkcifop()) goto 999

       ! oh, well, that's that...
       if (.not.fl) then
          errmsg = "Error reading symmetry."
          goto 999
       end if

       ! call spgs and hope for the best
       call spgs_wrap(seed,spg,.false.)
    endif

    ! rest of the seed information
    seed%isused = .true.
    seed%ismolecule = mol
    seed%cubic = .false.
    seed%border = 0d0
    seed%havex0 = .false.
    seed%molx0 = 0d0

999 continue

    ! restore the old values of x, y, and z
    if (ix) call setvariable("x",xo)
    if (iy) call setvariable("y",yo)
    if (iz) call setvariable("z",zo)

  contains
    function checkcifop()
      use tools_io, only: string
      logical :: checkcifop
      checkcifop = (cifelin_ == 0)
      if (checkcifop) then
         errmsg = ""
      else
         errmsg = trim(cifemsg_) // " (Line: " // string(cifelin_) // ")"
      end if
    end function checkcifop
  end subroutine read_cif_items

  !> Determine whether a given output file (.scf.out or .out) comes
  !> from a crystal or a quantum espresso calculation. To do this,
  !> try to find the "Program PWSCF" line in the output header.
  function is_espresso(file)
    use tools_io, only: fopen_read, fclose, getline_raw, equal, lower, lgetword

    logical :: is_espresso
    character*(*), intent(in) :: file !< Input file name

    integer :: lu, lp
    character(len=:), allocatable :: line, word1, word2

    is_espresso = .false.
    lu = fopen_read(file)
    if (lu < 0) return
    line = ""
    do while(getline_raw(lu,line))
       lp = 1
       word1 = lgetword(line,lp)
       word2 = lgetword(line,lp)
       is_espresso = (equal(word1,"program") .and. equal(word2,"pwscf"))
       if (is_espresso) exit
    end do
    call fclose(lu)

  end function is_espresso

  !> From QE, generate the lattice from the ibrav
  subroutine qe_latgen(ibrav,celldm,a1,a2,a3,errmsg)
    ! This subroutine has been adapted from parts of the Quantum
    ! ESPRESSO code, version 4.3.2.  
    ! Copyright (C) 2002-2009 Quantum ESPRESSO group
    ! This file is distributed under the terms of the
    ! GNU General Public License. See the file `License'
    ! in the root directory of the present distribution,
    ! or http://www.gnu.org/copyleft/gpl.txt .
    !-----------------------------------------------------------------------
    !     sets up the crystallographic vectors a1, a2, and a3.
    !
    !     ibrav is the structure index:
    !       1  cubic P (sc)                8  orthorhombic P
    !       2  cubic F (fcc)               9  one face centered orthorhombic
    !       3  cubic I (bcc)              10  all face centered orthorhombic
    !       4  hexagonal and trigonal P   11  body centered orthorhombic
    !       5  trigonal R, 3-fold axis c  12  monoclinic P (unique axis: c)
    !       6  tetragonal P (st)          13  one face centered monoclinic
    !       7  tetragonal I (bct)         14  triclinic P
    !     Also accepted:
    !       0  "free" structure          -12  monoclinic P (unique axis: b)
    !      -5  trigonal R, threefold axis along (111) 
    !
    !     NOTA BENE: all axis sets are right-handed
    !     Boxes for US PPs do not work properly with left-handed axis
    !
    integer, parameter :: dp = selected_real_kind(14,200)
    integer, intent(in) :: ibrav
    real(DP), intent(inout) :: celldm(6)
    real(DP), intent(out) :: a1(3), a2(3), a3(3)
    character(len=:), allocatable, intent(out) :: errmsg

    real(DP), parameter:: sr2 = 1.414213562373d0, sr3 = 1.732050807569d0
    integer :: ir
    real(DP) :: term, cbya, term1, term2, singam, sen

    errmsg = ""
    if (celldm(1) <= 0.d0) then
       errmsg = 'Wrong celldm(1).'
    elseif (celldm(2) <= 0.d0 .and. (ibrav == 8 .or. ibrav == 9 .or.&
       ibrav == 10 .or. ibrav == 11 .or. ibrav == 12 .or.&
       ibrav == -12 .or. ibrav == 13 .or. ibrav == 14)) then
       errmsg = 'Wrong celldm(2).'
    elseif (celldm(3) <= 0.d0 .and. (ibrav == 4 .or. ibrav == 6 .or.&
       ibrav == 7 .or. ibrav == 8 .or. ibrav == 9 .or. ibrav == 10 .or.&
       ibrav == 11 .or. ibrav == 12 .or. ibrav == -12 .or.&
       ibrav == 13 .or. ibrav == 14)) then
       errmsg = 'Wrong celldm(3).'
    else if ((celldm(4) <= -0.5d0 .or. celldm(4) >= 1) .and.&
       (ibrav == 5 .or. ibrav == -5)) then
       errmsg = 'Wrong celldm(4).'
    else if (celldm(4) >= 1.d0 .and. (ibrav == 12 .or. ibrav == 13 .or.&
       ibrav == 14)) then
       errmsg = 'Wrong celldm(4).'
    else if (celldm(5) >= 1.d0 .and. (ibrav == -12 .or. ibrav == 14)) then
       errmsg = 'Wrong celldm(5).'
    else if (celldm(6) >= 1.d0 .and. (ibrav == 14)) then
       errmsg = 'Wrong celldm(6).'
    end if
    if (len_trim(errmsg) > 0) return

    a1 = 0d0
    a2 = 0d0
    a3 = 0d0
    ! index of bravais lattice supplied
    if (ibrav == 1) then
       ! simple cubic lattice
       a1(1)=celldm(1)
       a2(2)=celldm(1)
       a3(3)=celldm(1)
       !
    else if (ibrav == 2) then
       ! fcc lattice
       term=celldm(1)/2.d0
       a1(1)=-term
       a1(3)=term
       a2(2)=term
       a2(3)=term
       a3(1)=-term
       a3(2)=term
       !
    else if (ibrav == 3) then
       ! bcc lattice
       term=celldm(1)/2.d0
       do ir=1,3
          a1(ir)=term
          a2(ir)=term
          a3(ir)=term
       end do
       a2(1)=-term
       a3(1)=-term
       a3(2)=-term
       !
    else if (ibrav == 4) then
       ! hexagonal lattice
       cbya=celldm(3)
       a1(1)=celldm(1)
       a2(1)=-celldm(1)/2.d0
       a2(2)=celldm(1)*sr3/2.d0
       a3(3)=celldm(1)*cbya
       !
    else if (ibrav == 5) then
       ! trigonal lattice, threefold axis along c (001)
       term1=sqrt(1.d0+2.d0*celldm(4))
       term2=sqrt(1.d0-celldm(4))
       a2(2)=sr2*celldm(1)*term2/sr3
       a2(3)=celldm(1)*term1/sr3
       a1(1)=celldm(1)*term2/sr2
       a1(2)=-a1(1)/sr3
       a1(3)= a2(3)
       a3(1)=-a1(1)
       a3(2)= a1(2)
       a3(3)= a2(3)
       !
    else if (ibrav ==-5) then
       ! trigonal lattice, threefold axis along (111)
       term1 = sqrt(1.0_dp + 2.0_dp*celldm(4))
       term2 = sqrt(1.0_dp - celldm(4))
       a1(1) = celldm(1)*(term1-2.0_dp*term2)/3.0_dp
       a1(2) = celldm(1)*(term1+term2)/3.0_dp
       a1(3) = a1(2)
       a2(1) = a1(3)
       a2(2) = a1(1)
       a2(3) = a1(2)
       a3(1) = a1(2)
       a3(2) = a1(3)
       a3(3) = a1(1)
    else if (ibrav == 6) then
       ! tetragonal lattice
       cbya=celldm(3)
       a1(1)=celldm(1)
       a2(2)=celldm(1)
       a3(3)=celldm(1)*cbya
       !
    else if (ibrav == 7) then
       ! body centered tetragonal lattice
       cbya=celldm(3)
       a2(1)=celldm(1)/2.d0
       a2(2)=a2(1)
       a2(3)=cbya*celldm(1)/2.d0
       a1(1)= a2(1)
       a1(2)=-a2(1)
       a1(3)= a2(3)
       a3(1)=-a2(1)
       a3(2)=-a2(1)
       a3(3)= a2(3)
       !
    else if (ibrav == 8) then
       ! Simple orthorhombic lattice
       a1(1)=celldm(1)
       a2(2)=celldm(1)*celldm(2)
       a3(3)=celldm(1)*celldm(3)
       !
    else if (ibrav == 9) then
       ! One face centered orthorhombic lattice
       a1(1) = 0.5d0 * celldm(1)
       a1(2) = a1(1) * celldm(2)
       a2(1) = - a1(1)
       a2(2) = a1(2)
       a3(3) = celldm(1) * celldm(3)
       !
    else if (ibrav == 10) then
       ! All face centered orthorhombic lattice
       a2(1) = 0.5d0 * celldm(1)
       a2(2) = a2(1) * celldm(2)
       a1(1) = a2(1)
       a1(3) = a2(1) * celldm(3)
       a3(2) = a2(1) * celldm(2)
       a3(3) = a1(3)
       !
    else if (ibrav == 11) then
       ! Body centered orthorhombic lattice
       a1(1) = 0.5d0 * celldm(1)
       a1(2) = a1(1) * celldm(2)
       a1(3) = a1(1) * celldm(3)
       a2(1) = - a1(1)
       a2(2) = a1(2)
       a2(3) = a1(3)
       a3(1) = - a1(1)
       a3(2) = - a1(2)
       a3(3) = a1(3)
       !
    else if (ibrav == 12) then
       ! Simple monoclinic lattice, unique (i.e. orthogonal to a) axis: c
       sen=sqrt(1.d0-celldm(4)**2)
       a1(1)=celldm(1)
       a2(1)=celldm(1)*celldm(2)*celldm(4)
       a2(2)=celldm(1)*celldm(2)*sen
       a3(3)=celldm(1)*celldm(3)
       !
    else if (ibrav ==-12) then
       ! Simple monoclinic lattice, unique axis: b (more common)
       sen=sqrt(1.d0-celldm(5)**2)
       a1(1)=celldm(1)
       a2(2)=celldm(1)*celldm(2)
       a3(1)=celldm(1)*celldm(3)*celldm(5)
       a3(3)=celldm(1)*celldm(3)*sen
       !
    else if (ibrav == 13) then
       ! One face centered monoclinic lattice
       sen = sqrt( 1.d0 - celldm(4) ** 2 )
       a1(1) = 0.5d0 * celldm(1) 
       a1(3) =-a1(1) * celldm(3)
       a2(1) = celldm(1) * celldm(2) * celldm(4)
       a2(2) = celldm(1) * celldm(2) * sen
       a3(1) = a1(1)
       a3(3) =-a1(3)
       !
    else if (ibrav == 14) then
       ! Triclinic lattice
       singam=sqrt(1.d0-celldm(6)**2)
       term= (1.d0+2.d0*celldm(4)*celldm(5)*celldm(6)-celldm(4)**2-celldm(5)**2-celldm(6)**2)
       if (term < 0.d0) then
          errmsg = 'Celldm do not make sense, check your data.'
          return
       end if
       term= sqrt(term/(1.d0-celldm(6)**2))
       a1(1)=celldm(1)
       a2(1)=celldm(1)*celldm(2)*celldm(6)
       a2(2)=celldm(1)*celldm(2)*singam
       a3(1)=celldm(1)*celldm(3)*celldm(5)
       a3(2)=celldm(1)*celldm(3)*(celldm(4)-celldm(5)*celldm(6))/singam
       a3(3)=celldm(1)*celldm(3)*term
       !
    else
       errmsg = 'Nonexistent bravais lattice.'
    end if

  end subroutine qe_latgen

  !> Wrapper to the spgs module. Sets the symetry in a crystal seed. 
  !> (including seed%havesym but not seed%findsym). If the spg
  !> was not correct, keep havesym = 0 and do nothing else.
  subroutine spgs_wrap(seed,spg,usespgr)
    use spgs, only: spgs_ncv, spgs_cen, spgs_n, spgs_m, spgs_driver
    class(crystalseed), intent(inout) :: seed
    character*(*), intent(in) :: spg
    logical, intent(in) :: usespgr

    if (spgs_driver(spg,usespgr)) then
       seed%ncv = spgs_ncv
       if (allocated(seed%cen)) deallocate(seed%cen)
       allocate(seed%cen(3,seed%ncv))
       seed%cen(:,1:seed%ncv) = real(spgs_cen(:,1:seed%ncv),8) / 12d0
       seed%neqv = spgs_n
       if (allocated(seed%rotm)) deallocate(seed%rotm)
       allocate(seed%rotm(3,4,spgs_n))
       seed%rotm = real(spgs_m(:,:,1:spgs_n),8)
       seed%rotm(:,4,:) = seed%rotm(:,4,:) / 12d0
       seed%havesym = 1
       seed%checkrepeats = 0
    else
       seed%havesym = 0
       seed%checkrepeats = 0
    end if

  end subroutine spgs_wrap

end submodule proc
