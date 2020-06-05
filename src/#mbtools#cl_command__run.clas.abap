************************************************************************
* /MBTOOLS/CL_COMMAND_RUN
* MBT Command - Run
*
* (c) MBT 2020 https://marcbernardtools.com/
************************************************************************
CLASS /mbtools/cl_command__run DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES /mbtools/if_command .

    ALIASES execute
      FOR /mbtools/if_command~execute .

    METHODS constructor .
  PROTECTED SECTION.

  PRIVATE SECTION.

    ALIASES command
      FOR /mbtools/if_command~mo_command .

    METHODS run_listcube
      IMPORTING
        !is_tadir_key  TYPE /mbtools/if_definitions=>ty_tadir_key
      RETURNING
        VALUE(rv_exit) TYPE abap_bool .
    METHODS run_tabl
      IMPORTING
        !is_tadir_key  TYPE /mbtools/if_definitions=>ty_tadir_key
      RETURNING
        VALUE(rv_exit) TYPE abap_bool .
    METHODS run_func
      IMPORTING
        !is_tadir_key  TYPE /mbtools/if_definitions=>ty_tadir_key
      RETURNING
        VALUE(rv_exit) TYPE abap_bool .
    METHODS run_prog
      IMPORTING
        !is_tadir_key  TYPE /mbtools/if_definitions=>ty_tadir_key
      RETURNING
        VALUE(rv_exit) TYPE abap_bool .
    METHODS run_tran
      IMPORTING
        !is_tadir_key  TYPE /mbtools/if_definitions=>ty_tadir_key
      RETURNING
        VALUE(rv_exit) TYPE abap_bool .
ENDCLASS.



CLASS /MBTOOLS/CL_COMMAND__RUN IMPLEMENTATION.


  METHOD /mbtools/if_command~execute.

    DATA:
      lv_object      TYPE string,
      lv_object_name TYPE string,
      lv_tadir_count TYPE i,
      ls_tadir_key   TYPE /mbtools/if_definitions=>ty_tadir_key.

    " Split parameters into object and object name
    command->split(
      EXPORTING
        iv_parameters = iv_parameters
      IMPORTING
        ev_operator   = lv_object
        ev_operand    = lv_object_name ).

    IF lv_object IS INITIAL.
      CONCATENATE
        /mbtools/if_command_field=>c_objects_db
        /mbtools/if_command_field=>c_objects_bw
        /mbtools/if_command_field=>c_objects_exec
        INTO lv_object SEPARATED BY ','.
    ENDIF.

    " Select objects
    command->select(
      EXPORTING
        iv_object   = lv_object
        iv_obj_name = lv_object_name ).

    " Filter table types to ones that work in SE16
    command->filter_tabl( ).

    " Add object texts
    command->text( ).

    DO.
      " Pick exactly one object
      command->pick(
        IMPORTING
          es_tadir_key = ls_tadir_key
          ev_count     = lv_tadir_count
        EXCEPTIONS
          cancelled   = 1
          OTHERS      = 2 ).
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      " Run object
      CASE ls_tadir_key-object.
        WHEN /mbtools/if_command_field=>c_objects_db-tabl OR
             /mbtools/if_command_field=>c_objects_db-view.

          rv_exit = run_tabl( is_tadir_key = ls_tadir_key ).

        WHEN /mbtools/if_command_field=>c_objects_exec-prog.

          rv_exit = run_prog( is_tadir_key = ls_tadir_key ).

        WHEN /mbtools/if_command_field=>c_objects_exec-tran.

          rv_exit = run_tran( is_tadir_key = ls_tadir_key ).

        WHEN /mbtools/if_command_field=>c_objects_exec-func.

          rv_exit = run_func( is_tadir_key = ls_tadir_key ).

        WHEN OTHERS.

          rv_exit = run_listcube( is_tadir_key = ls_tadir_key ).

      ENDCASE.

      IF lv_tadir_count = 1.
        EXIT.
      ENDIF.
    ENDDO.

  ENDMETHOD.


  METHOD constructor.

    CREATE OBJECT command.

  ENDMETHOD.


  METHOD run_func.

    DATA:
      lv_funcname TYPE funcname.

    CHECK is_tadir_key-object = /mbtools/if_command_field=>c_objects_exec-func.

    " Check if function module exists
    SELECT SINGLE funcname FROM tfdir INTO lv_funcname
      WHERE funcname = is_tadir_key-obj_name.
    IF sy-subrc <> 0.
      MESSAGE e004 WITH is_tadir_key-obj_name.
      RETURN.
    ENDIF.

    " Authorization check on S_DEVELOP happens in function RS_TESTFRAME_CALL
    SUBMIT rs_testframe_call WITH funcn = lv_funcname AND RETURN.

    rv_exit = abap_true.

  ENDMETHOD.


  METHOD run_listcube.

    CHECK /mbtools/if_command_field=>c_objects_bw CS is_tadir_key-object.

    " Authorization check for LISTCUBE
    CALL FUNCTION 'AUTHORITY_CHECK_TCODE'
      EXPORTING
        tcode  = 'LISTCUBE'
      EXCEPTIONS
        ok     = 1
        not_ok = 2
        OTHERS = 3.
    IF sy-subrc = 1.
      " Run LISTCUBE with additional authorization checks on InfoProvider
      SUBMIT rsdd_show_icube
        WITH p_dbagg = abap_true
        WITH p_dta   = is_tadir_key-obj_name
        WITH p_tlogo = is_tadir_key-object
        AND RETURN.

      rv_exit = abap_true.
    ENDIF.

  ENDMETHOD.


  METHOD run_prog.

    DATA:
      ls_trdir_entry TYPE trdir.

    CHECK is_tadir_key-object = /mbtools/if_command_field=>c_objects_exec-prog.

    " Check if executable program exists
    SELECT SINGLE * FROM trdir INTO ls_trdir_entry
      WHERE name = is_tadir_key-obj_name AND subc = '1'.
    IF sy-subrc = 0.
      " Run program with authorization check
      CALL FUNCTION 'SUBMIT_REPORT'
        EXPORTING
          report           = ls_trdir_entry-name
          rdir             = ls_trdir_entry
          ret_via_leave    = abap_true
        EXCEPTIONS
          just_via_variant = 1
          no_submit_auth   = 2
          OTHERS           = 3.
      IF sy-subrc = 0.
        rv_exit = abap_true.
      ELSEIF sy-subrc = 2.
        MESSAGE i149(00) WITH ls_trdir_entry-name.
      ENDIF.
    ELSE.
      MESSAGE i541(00) WITH ls_trdir_entry-name.
    ENDIF.

  ENDMETHOD.


  METHOD run_tabl.

    DATA:
      ls_dd02l TYPE dd02l,
      lv_subrc TYPE sy-subrc.

    CHECK /mbtools/if_command_field=>c_objects_db CS is_tadir_key-object.

    " For tables we check if there's any data to avoid pointless SE16 selection
    SELECT SINGLE * FROM dd02l INTO ls_dd02l
      WHERE tabname = is_tadir_key-obj_name AND as4local = 'A'.
    IF sy-subrc = 0.
      CALL FUNCTION 'DD_EXISTS_DATA'
        EXPORTING
          reftab          = ls_dd02l-sqltab
          tabclass        = ls_dd02l-tabclass
          tabname         = ls_dd02l-tabname
        IMPORTING
          subrc           = lv_subrc
        EXCEPTIONS
          missing_reftab  = 1
          sql_error       = 2
          buffer_overflow = 3
          unknown_error   = 4
          OTHERS          = 5.
      IF sy-subrc = 0 AND lv_subrc = 2.
        MESSAGE s005 WITH ls_dd02l-tabname.
        rv_exit = abap_true.
        RETURN.
      ENDIF.
    ENDIF.

    " Run SE16 with authorization check
    CALL FUNCTION 'RS_TABLE_LIST_CREATE'
      EXPORTING
        table_name         = is_tadir_key-obj_name
      EXCEPTIONS
        table_is_structure = 1
        table_not_exists   = 2
        db_not_exists      = 3
        no_permission      = 4
        no_change_allowed  = 5
        table_is_gtt       = 6
        OTHERS             = 7.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE 'S' NUMBER sy-msgno
        WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.

    rv_exit = abap_true.

  ENDMETHOD.


  METHOD run_tran.

    DATA:
      lv_tcode TYPE sy-tcode.

    CHECK is_tadir_key-object = /mbtools/if_command_field=>c_objects_exec-tran.

    " Check if transaction exists
    SELECT SINGLE tcode FROM tstc INTO lv_tcode
      WHERE tcode = is_tadir_key-obj_name.
    IF sy-subrc = 0.
      " Run transaction with authorization check
      CALL FUNCTION 'AUTHORITY_CHECK_TCODE'
        EXPORTING
          tcode  = lv_tcode
        EXCEPTIONS
          ok     = 0
          not_ok = 2
          OTHERS = 3.
      IF sy-subrc = 0.
        CALL TRANSACTION lv_tcode.                       "#EC CI_CALLTA

        rv_exit = abap_true.
      ELSE.
        MESSAGE i172(00) WITH lv_tcode.
      ENDIF.
    ELSE.
      MESSAGE i031(00) WITH lv_tcode.
    ENDIF.

  ENDMETHOD.
ENDCLASS.